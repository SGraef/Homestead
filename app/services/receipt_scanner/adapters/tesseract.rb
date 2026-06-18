# frozen_string_literal: true
# typed: true

require "open3"
require "tmpdir"

module ReceiptScanner
  module Adapters
    # Default OCR adapter shelling out to the local `tesseract` binary.
    # Requires `tesseract-ocr` (with the desired language packs) and, for PDF
    # support, `poppler-utils` (`pdftoppm`) to be installed in the runtime
    # image (see Dockerfile / Dockerfile.dev).
    #
    # PDFs are rasterized to PNG via `pdftoppm` at 200 DPI, then each page is
    # OCR'd individually and the page texts are concatenated with a blank line
    # between them.
    class Tesseract
      DEFAULT_LANG = ENV.fetch("OCR_LANG", "eng+deu")
      DEFAULT_PSM  = ENV.fetch("OCR_PSM",  "6")
      # Fallback PSMs tried when the configured PSM returns empty text.
      # PSM 4 = single column of text (good for narrow receipts), PSM 11
      # = sparse text (good for handheld phone photos with noisy
      # background). Order matters: cheapest first.
      FALLBACK_PSMS = %w[4 11].freeze
      PDF_DPI       = ENV.fetch("OCR_PDF_DPI", "200").to_i
      # Tesseract uses OpenMP internally and by default spawns one
      # worker per available core, which can pin every CPU on a small
      # box during a scan. Cap it via OMP_THREAD_LIMIT, configurable
      # so beefy hosts can opt back into parallelism.
      THREAD_LIMIT = ENV.fetch("OCR_THREAD_LIMIT", "2")
      # Photo preprocessing: auto-orient (EXIF), grayscale, contrast
      # normalize, upscale anything narrower than this so tesseract --
      # which trains on ~300 DPI text -- has enough pixels per glyph.
      # Phones routinely produce 700-800 px photos of receipts that
      # OCR to nothing without this. Set OCR_PREPROCESS=0 to disable.
      PREPROCESS_ENABLED = ENV.fetch("OCR_PREPROCESS", "1") != "0"
      MIN_PREPROCESS_WIDTH = ENV.fetch("OCR_MIN_WIDTH", "1800").to_i

      # Resource caps handed to every `convert` invocation. These are the
      # *enforced* hardening layer: ImageMagick's policy.xml is silently
      # ignored by the Debian reproducible-build IM6 in our images, but
      # command-line `-limit` flags (and the matching MAGICK_*_LIMIT env vars
      # set in the Dockerfiles) are honoured. They stop decompression bombs
      # and runaway memory/time from a malicious receipt upload.
      CONVERT_LIMITS = %w[
        -limit memory 256MiB
        -limit map 512MiB
        -limit disk 1GiB
        -limit area 128MP
        -limit width 16KP
        -limit height 16KP
        -limit time 120
      ].freeze

      # Magic-byte allowlist of raster formats we hand to `convert`. A file
      # whose extension says ".jpg" but whose bytes are an MVG/MSL/SVG script
      # would otherwise be auto-detected and *executed* by ImageMagick (the
      # classic "ImageTragick" coder-RCE/SSRF vector). policy.xml would
      # normally disable those coders, but it is inert in our IM6 build, so we
      # gate at the application layer instead: anything not on this list skips
      # `convert` entirely and is OCR'd as-is (tesseract/Leptonica have no
      # scripting coders). HEIF/HEIC (iPhone uploads) carry an "ftyp" box at
      # offset 4.
      RASTER_MAGIC_PREFIXES = [
        "\xFF\xD8\xFF".b,          # JPEG
        "\x89PNG\r\n\x1A\n".b,     # PNG
        "GIF87a".b, "GIF89a".b,    # GIF
        "BM".b,                    # BMP
        "II*\x00".b, "MM\x00*".b   # TIFF (little/big endian)
      ].freeze

      def initialize(lang: DEFAULT_LANG, psm: DEFAULT_PSM, pdf_dpi: PDF_DPI)
        @lang             = lang
        @psm              = psm
        @pdf_dpi          = pdf_dpi
        @line_confidences = {}
      end

      # OCR confidence (0-100) keyed by reconstructed line text, populated as a
      # side effect of the most recent {#extract_text}. Best-effort: empty when
      # the TSV pass fails, and missing for lines OCR'd with a fallback PSM.
      attr_reader :line_confidences

      # @param file_path [String]
      # @return [String] raw OCR text (concatenated across pages for PDFs)
      def extract_text(file_path)
        if pdf?(file_path)
          extract_from_pdf(file_path)
        else
          ocr_image_with_fallback(file_path)
        end
      end

      private

      # Env passed to every OCR subprocess. OMP_THREAD_LIMIT caps the
      # OpenMP pool tesseract spawns. OMP_DYNAMIC=FALSE stops the
      # runtime from re-expanding the pool past the limit under load.
      def ocr_env
        { "OMP_THREAD_LIMIT" => THREAD_LIMIT.to_s, "OMP_DYNAMIC" => "FALSE" }
      end

      # Detect by file magic rather than extension so misnamed uploads still
      # take the right branch.
      def pdf?(path)
        File.binread(path, 4) == "%PDF"
      rescue StandardError
        false
      end

      # True only for files whose leading bytes are a known raster image, plus
      # the WEBP and HEIF/HEIC container formats (brand box at offset 4). Used
      # to keep crafted script files (MVG/MSL/SVG) away from ImageMagick.
      def raster_image?(path)
        head = File.binread(path, 16).to_s.b
        return true if RASTER_MAGIC_PREFIXES.any? { |p| head.start_with?(p) }
        return true if head.start_with?("RIFF".b) && head[8, 4] == "WEBP".b
        return true if head[4, 4] == "ftyp".b # HEIF/HEIC/AVIF family

        false
      rescue StandardError
        false
      end

      def run_tesseract(image_path, psm: @psm)
        out, err, status = Open3.capture3(
          ocr_env,
          "tesseract", image_path, "stdout", "-l", @lang, "--psm", psm
        )
        unless status.success?
          msg = err.to_s.strip.presence || "tesseract exit #{status.exitstatus}"
          raise OcrError, "tesseract failed: #{msg}"
        end
        out
      rescue Errno::ENOENT
        raise OcrError, "tesseract binary not found in PATH (install tesseract-ocr)"
      end

      # Preprocess (if enabled) then OCR. If the configured PSM returns
      # empty text -- typical for handheld phone photos where the
      # default PSM 6 can't find a uniform block -- retry on the
      # preprocessed image with the fallback PSMs before giving up.
      def ocr_image_with_fallback(image_path)
        if PREPROCESS_ENABLED
          Dir.mktmpdir("pantria-ocr-pre") do |dir|
            prepared = File.join(dir, "prepared.png")
            preprocess_image!(image_path, prepared)
            ocr_text_and_confidence(prepared)
          end
        else
          ocr_text_and_confidence(image_path)
        end
      end

      # Run the (unchanged) text OCR, then a separate TSV pass on the same image
      # to capture per-line confidence. Returns the text; stashes confidences.
      def ocr_text_and_confidence(image_path)
        text = ocr_with_fallback_psms(image_path)
        @line_confidences = compute_line_confidences(image_path)
        text
      end

      def ocr_with_fallback_psms(image_path)
        text = run_tesseract(image_path, psm: @psm)
        return text if text.strip.present?

        FALLBACK_PSMS.each do |psm|
          next if psm == @psm.to_s

          text = run_tesseract(image_path, psm: psm)
          return text if text.strip.present?
        end
        text
      end

      # ImageMagick pipeline tuned for photographed receipts:
      #   -auto-orient   honour EXIF rotation; phones store landscape as
      #                  rotated portrait + a flag and tesseract reads
      #                  the bytes literally otherwise.
      #   -colorspace Gray + -normalize bring contrast back when the
      #                  paper is grey-shadowed (typical indoor photo).
      #   -resize WIDTHx scales up small photos so tesseract gets enough
      #                  pixels per glyph (it trains on ~300 DPI).
      #   -sharpen       cheap edge sharpening helps the LSTM model.
      #   -strip         drops EXIF (we don't need it post-orient).
      def preprocess_image!(src_path, dst_path)
        # Never feed a non-raster file to ImageMagick: a misnamed MVG/MSL/SVG
        # script would be auto-detected and executed (ImageTragick). OCR the
        # original directly instead -- tesseract has no scripting coders.
        unless raster_image?(src_path)
          Rails.logger.warn("[ReceiptScanner] unrecognized image format; skipping convert preprocess")
          return FileUtils.cp(src_path, dst_path)
        end

        out, err, status = Open3.capture3(
          ocr_env,
          "convert", *CONVERT_LIMITS, src_path,
          "-auto-orient",
          "-colorspace", "Gray",
          "-normalize",
          "-resize", "#{MIN_PREPROCESS_WIDTH}x>",
          "-sharpen", "0x1",
          "-strip",
          dst_path
        )
        return if status.success? && File.exist?(dst_path) && File.size(dst_path).positive?

        # If preprocessing fails (missing convert, exotic format, ...),
        # fall back to the original. Better to OCR the raw image than
        # to fail the whole receipt.
        msg = err.to_s.strip.presence || out.to_s.strip.presence || "convert exit #{status.exitstatus}"
        Rails.logger.warn("[ReceiptScanner] preprocess failed (#{msg}); using original")
        FileUtils.cp(src_path, dst_path)
      rescue Errno::ENOENT
        Rails.logger.warn("[ReceiptScanner] ImageMagick `convert` not found; skipping preprocess")
        FileUtils.cp(src_path, dst_path)
      end

      def extract_from_pdf(pdf_path)
        Dir.mktmpdir("pantria-ocr") do |dir|
          prefix = File.join(dir, "page")
          rasterize_pdf!(pdf_path, prefix)
          pages = Dir.glob("#{prefix}-*.png")
          raise OcrError, "PDF rasterized to zero pages" if pages.empty?

          confidences = {}
          text = pages.map do |p|
            page_text = run_tesseract(p)
            confidences.merge!(compute_line_confidences(p))
            page_text
          end.join("\n\n")
          @line_confidences = confidences
          text
        end
      end

      # Run Tesseract in TSV mode and average each text line's word confidences.
      # Best-effort: returns {} if Tesseract isn't available or errors, so OCR
      # confidence never blocks the text extraction it accompanies.
      def compute_line_confidences(image_path)
        out, _err, status = Open3.capture3(
          ocr_env,
          "tesseract", image_path, "stdout", "-l", @lang, "--psm", @psm.to_s, "tsv"
        )
        return {} unless status.success?

        parse_tsv_confidences(out)
      rescue Errno::ENOENT
        {}
      end

      # Parse Tesseract TSV: group word-level rows (level 5) by their
      # page/block/par/line key, join the words into the line text, and average
      # the non-negative word confidences. @return [Hash{String=>Integer}]
      def parse_tsv_confidences(tsv_output)
        groups = {}
        tsv_output.to_s.each_line.with_index do |row, index|
          next if index.zero? # header row

          cols = row.chomp.split("\t")
          next if cols.length < 12 || cols[0].to_i != 5

          word = cols[11].to_s
          next if word.strip.empty?

          group = (groups[cols[1, 4].join("-")] ||= { words: [], confs: [] })
          group[:words] << word
          conf = cols[10].to_f
          group[:confs] << conf if conf >= 0
        end

        groups.each_with_object({}) do |(_key, group), acc|
          line = group[:words].join(" ").strip
          next if line.empty? || group[:confs].empty?

          acc[line] = (group[:confs].sum / group[:confs].size).round
        end
      end

      def rasterize_pdf!(pdf_path, prefix)
        out, err, status = Open3.capture3(
          ocr_env,
          "pdftoppm", "-r", @pdf_dpi.to_s, "-png", pdf_path, prefix
        )
        return if status.success?

        msg = err.to_s.strip.presence || out.to_s.strip.presence || "pdftoppm exit #{status.exitstatus}"
        raise OcrError, "pdftoppm failed: #{msg}"
      rescue Errno::ENOENT
        raise OcrError, "pdftoppm binary not found in PATH (install poppler-utils)"
      end
    end
  end
end

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

      def initialize(lang: DEFAULT_LANG, psm: DEFAULT_PSM, pdf_dpi: PDF_DPI)
        @lang    = lang
        @psm     = psm
        @pdf_dpi = pdf_dpi
      end

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
            ocr_with_fallback_psms(prepared)
          end
        else
          ocr_with_fallback_psms(image_path)
        end
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
        out, err, status = Open3.capture3(
          ocr_env,
          "convert", src_path,
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

          pages.map { |p| run_tesseract(p) }.join("\n\n")
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

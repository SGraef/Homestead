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
      PDF_DPI      = ENV.fetch("OCR_PDF_DPI", "200").to_i

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
          run_tesseract(file_path)
        end
      end

      private

      # Detect by file magic rather than extension so misnamed uploads still
      # take the right branch.
      def pdf?(path)
        File.binread(path, 4) == "%PDF"
      rescue StandardError
        false
      end

      def run_tesseract(image_path)
        out, err, status = Open3.capture3(
          "tesseract", image_path, "stdout", "-l", @lang, "--psm", @psm
        )
        unless status.success?
          msg = err.to_s.strip.presence || "tesseract exit #{status.exitstatus}"
          raise OcrError, "tesseract failed: #{msg}"
        end
        out
      rescue Errno::ENOENT
        raise OcrError, "tesseract binary not found in PATH (install tesseract-ocr)"
      end

      def extract_from_pdf(pdf_path)
        Dir.mktmpdir("pantria-ocr") do |dir|
          prefix = File.join(dir, "page")
          rasterize_pdf!(pdf_path, prefix)
          pages = Dir.glob("#{prefix}-*.png").sort
          raise OcrError, "PDF rasterized to zero pages" if pages.empty?

          pages.map { |p| run_tesseract(p) }.join("\n\n")
        end
      end

      def rasterize_pdf!(pdf_path, prefix)
        out, err, status = Open3.capture3(
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

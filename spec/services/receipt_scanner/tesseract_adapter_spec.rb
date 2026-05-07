# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ReceiptScanner::Adapters::Tesseract do
  subject(:adapter) { described_class.new }

  describe "#extract_text" do
    let(:tmp) { Dir.mktmpdir("ocr-test") }
    after    { FileUtils.remove_entry(tmp) }

    it "shells out to tesseract for an image" do
      img_path = File.join(tmp, "img.png")
      File.binwrite(img_path, "\x89PNG\r\n\x1a\nfake")

      allow(Open3).to receive(:capture3)
        .with("tesseract", img_path, "stdout", "-l", anything, "--psm", anything)
        .and_return(["raw image text", "", instance_double(Process::Status, success?: true, exitstatus: 0)])

      expect(adapter.extract_text(img_path)).to eq("raw image text")
    end

    it "rasterizes a PDF and concatenates per-page OCR" do
      pdf_path = File.join(tmp, "receipt.pdf")
      File.binwrite(pdf_path, "%PDF-1.4\n%%EOF")

      allow(Open3).to receive(:capture3) do |*args|
        case args[0]
        when "pdftoppm"
          # Simulate pdftoppm dropping two PNGs in the work dir.
          prefix = args.last
          File.write("#{prefix}-1.png", "x")
          File.write("#{prefix}-2.png", "y")
          ["", "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        when "tesseract"
          page = args[1]
          ["text from #{File.basename(page)}", "",
           instance_double(Process::Status, success?: true, exitstatus: 0)]
        end
      end

      result = adapter.extract_text(pdf_path)
      expect(result).to include("text from page-1.png")
      expect(result).to include("text from page-2.png")
      expect(result).to match(/page-1\.png\n\ntext from page-2\.png/)
    end

    it "raises OcrError when pdftoppm fails" do
      pdf_path = File.join(tmp, "broken.pdf")
      File.binwrite(pdf_path, "%PDF-1.4\nbroken")

      allow(Open3).to receive(:capture3)
        .with("pdftoppm", any_args)
        .and_return(["", "fatal: not a real PDF", instance_double(Process::Status, success?: false, exitstatus: 1)])

      expect { adapter.extract_text(pdf_path) }
        .to raise_error(ReceiptScanner::OcrError, /pdftoppm failed/)
    end
  end
end

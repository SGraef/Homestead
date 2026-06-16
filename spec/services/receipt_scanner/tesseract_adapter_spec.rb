# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ReceiptScanner::Adapters::Tesseract do
  subject(:adapter) { described_class.new }

  describe "#extract_text" do
    let(:tmp) { Dir.mktmpdir("ocr-test") }

    after { FileUtils.remove_entry(tmp) }

    # OCR subprocesses now take an env hash as the first arg (capping
    # OpenMP threads). Matchers below ignore the env, just check the
    # command + args.

    it "preprocesses with ImageMagick, then shells out to tesseract for an image" do
      img_path = File.join(tmp, "img.png")
      File.binwrite(img_path, "\x89PNG\r\n\x1a\nfake")

      allow(Open3).to receive(:capture3) do |_env, cmd, *rest|
        case cmd
        when "convert"
          # Last arg is the destination path; create a fake output file
          # so `File.exist?` + `File.size.positive?` succeed.
          File.binwrite(rest.last, "\x89PNG\r\n\x1a\npre")
          ["", "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        when "tesseract"
          ["raw image text", "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        end
      end

      expect(adapter.extract_text(img_path)).to eq("raw image text")
    end

    it "passes enforced resource -limit flags to convert" do
      img_path = File.join(tmp, "img.png")
      File.binwrite(img_path, "\x89PNG\r\n\x1a\nfake")

      convert_args = nil
      allow(Open3).to receive(:capture3) do |_env, cmd, *rest|
        case cmd
        when "convert"
          convert_args = rest
          File.binwrite(rest.last, "\x89PNG\r\n\x1a\npre")
          ["", "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        when "tesseract"
          ["text", "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        end
      end

      adapter.extract_text(img_path)
      joined = convert_args.join(" ")
      expect(joined).to include("-limit memory 256MiB")
      expect(joined).to include("-limit area 128MP")
      expect(joined).to include("-limit width 16KP")
      expect(joined).to include("-limit time 120")
    end

    it "skips convert and OCRs the original when the file is not a known raster image" do
      # A misnamed ImageMagick script (MVG) -- never hand this to convert.
      script_path = File.join(tmp, "evil.png")
      File.binwrite(script_path, "push graphic-context\nimage over 0,0 0,0 'http://x/'\n")

      called = []
      allow(Open3).to receive(:capture3) do |_env, cmd, *_rest|
        called << cmd
        ["original text", "", instance_double(Process::Status, success?: true, exitstatus: 0)] if cmd == "tesseract"
      end

      expect(Rails.logger).to receive(:warn).with(/unrecognized image format/i)
      expect(adapter.extract_text(script_path)).to eq("original text")
      expect(called).not_to include("convert")
    end

    it "retries with fallback PSMs when the configured PSM returns empty text" do
      img_path = File.join(tmp, "img.png")
      File.binwrite(img_path, "\x89PNG\r\n\x1a\nfake")

      psm_calls = []
      allow(Open3).to receive(:capture3) do |_env, cmd, *rest|
        case cmd
        when "convert"
          File.binwrite(rest.last, "\x89PNG\r\n\x1a\npre")
          ["", "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        when "tesseract"
          # `--psm` argument index varies; just grab the value after it.
          psm = rest[rest.index("--psm") + 1]
          psm_calls << psm
          body = psm == "11" ? "PSM-11 recovered text" : ""
          [body, "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        end
      end

      expect(adapter.extract_text(img_path)).to eq("PSM-11 recovered text")
      expect(psm_calls).to eq(%w[6 4 11]) # default PSM 6 + both fallbacks
    end

    it "falls back to the original image when ImageMagick is missing" do
      img_path = File.join(tmp, "img.png")
      File.binwrite(img_path, "\x89PNG\r\n\x1a\nfake")

      allow(Open3).to receive(:capture3) do |_env, cmd, *_rest|
        case cmd
        when "convert"   then raise Errno::ENOENT
        when "tesseract" then ["fallback text", "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        end
      end

      expect(Rails.logger).to receive(:warn).with(/convert.*not found/i)
      expect(adapter.extract_text(img_path)).to eq("fallback text")
    end

    it "rasterizes a PDF and concatenates per-page OCR" do
      pdf_path = File.join(tmp, "receipt.pdf")
      File.binwrite(pdf_path, "%PDF-1.4\n%%EOF")

      allow(Open3).to receive(:capture3) do |*args|
        # First arg is the env hash; the command and its args follow.
        _env, cmd, *rest = args
        case cmd
        when "pdftoppm"
          prefix = rest.last
          File.write("#{prefix}-1.png", "x")
          File.write("#{prefix}-2.png", "y")
          ["", "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        when "tesseract"
          page = rest[0]
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
        .with(kind_of(Hash), "pdftoppm", any_args)
        .and_return(["", "fatal: not a real PDF", instance_double(Process::Status, success?: false, exitstatus: 1)])

      expect { adapter.extract_text(pdf_path) }
        .to raise_error(ReceiptScanner::OcrError, /pdftoppm failed/)
    end

    it "caps OpenMP threads when calling tesseract" do
      img_path = File.join(tmp, "img.png")
      File.binwrite(img_path, "\x89PNG\r\n\x1a\nfake")

      tesseract_env = nil
      allow(Open3).to receive(:capture3) do |env, cmd, *rest|
        case cmd
        when "convert"
          File.binwrite(rest.last, "\x89PNG\r\n\x1a\npre")
          ["", "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        when "tesseract"
          tesseract_env = env
          ["text", "", instance_double(Process::Status, success?: true, exitstatus: 0)]
        end
      end

      adapter.extract_text(img_path)
      expect(tesseract_env).to include("OMP_THREAD_LIMIT", "OMP_DYNAMIC")
      expect(tesseract_env["OMP_THREAD_LIMIT"]).to match(/\A\d+\z/)
    end
  end
end

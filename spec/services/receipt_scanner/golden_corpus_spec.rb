# frozen_string_literal: true
# typed: false

require "rails_helper"

# Golden-file regression harness for the receipt parser — the data-corruption
# sensitive path. Each spec/fixtures/receipts/<name>.txt (synthesized German
# retailer OCR text) is paired with <name>.yml (the parser's expected output).
# A parser change that alters extraction shows up here as a failing snapshot:
# review the diff, then regenerate the .yml deliberately (and bump
# ReceiptScanner::Parser::VERSION if the change is meant to re-parse old
# receipts). Add coverage by dropping a new .txt/.yml pair into the fixtures
# directory — the example is generated automatically.
RSpec.describe "ReceiptScanner::Parser golden corpus" do # rubocop:disable RSpec/DescribeClass
  # rubocop:disable RSpec/LeakyLocalVariable -- examples are generated from the
  # fixture files, so the loop locals are read inside each example by design.
  fixtures_dir = Rails.root.join("spec/fixtures/receipts")

  Dir.glob(fixtures_dir.join("*.txt")).each do |txt|
    name = File.basename(txt, ".txt")

    it "parses #{name} to its golden snapshot" do
      expected = YAML.safe_load_file(fixtures_dir.join("#{name}.yml"), permitted_classes: [Date])
      result   = ReceiptScanner::Parser.parse(File.read(txt))

      aggregate_failures do
        expect(result.store_name).to eq(expected["store_name"])
        expect(result.purchased_on).to eq(expected["purchased_on"])
        expect(result.subtotal_cents).to eq(expected["subtotal_cents"])
        expect(result.parser_version).to eq(expected["parser_version"])

        actual_items = result.line_items.map do |li|
          { "name" => li.name, "quantity" => li.quantity, "total_cents" => li.total_cents }
        end
        expect(actual_items).to eq(expected["line_items"])
      end
    end
  end
  # rubocop:enable RSpec/LeakyLocalVariable
end

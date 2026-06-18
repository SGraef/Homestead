# frozen_string_literal: true

class AddParserVersionToReceipts < ActiveRecord::Migration[8.0]
  def change
    # Which ReceiptScanner::Parser::VERSION produced this receipt's line items.
    # Lets a future task find receipts parsed by an older version and re-process
    # them idempotently after a parser improvement. Nullable for legacy rows.
    add_column :receipts, :parser_version, :integer
  end
end

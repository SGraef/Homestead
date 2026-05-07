# frozen_string_literal: true
# typed: ignore

class AddTokenTypeToBringConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :bring_connections, :token_type, :string, limit: 32, default: "Bearer"
  end
end

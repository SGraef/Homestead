# frozen_string_literal: true
# typed: ignore

# Backing table for solid_cable (DB-backed Action Cable pub/sub). Lives in the
# primary database — SolidCable::Record only overrides the connection when
# SolidCable.connects_to is set, which we deliberately leave unset. Schema
# copied from solid_cable 3.0's install template.
class CreateSolidCableMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_cable_messages do |t|
      t.binary   :channel,      limit: 1024,      null: false
      t.binary   :payload,      limit: 536_870_912, null: false
      t.datetime :created_at,   null: false
      t.integer  :channel_hash, limit: 8,         null: false
      t.index :channel,      name: "index_solid_cable_messages_on_channel"
      t.index :channel_hash, name: "index_solid_cable_messages_on_channel_hash"
      t.index :created_at,   name: "index_solid_cable_messages_on_created_at"
    end
  end
end

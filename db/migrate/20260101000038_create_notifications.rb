# frozen_string_literal: true
# typed: ignore

# In-app notification ledger. Push (a later phase) is just one delivery channel;
# this persisted row is the reliable baseline shown in the top-nav bell, so the
# feature works even where push doesn't (iOS/desktop). `dedup_key` gives
# idempotency (the same domain event never produces two rows).
class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications do |t|
      t.references :household, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true # recipient
      t.references :actor, null: true,  foreign_key: { to_table: :users } # who caused it
      t.references :notifiable, polymorphic: true, null: true # -> Todo / TodoComment
      t.string   :kind,      null: false
      t.string   :title,     null: false
      t.text     :body
      t.string   :url
      t.string   :dedup_key, null: false
      t.datetime :read_at
      t.timestamps
    end

    add_index :notifications, :dedup_key, unique: true
    add_index :notifications, %i[user_id read_at]
  end
end

# frozen_string_literal: true
# typed: ignore

# @see https://github.com/Sorcery/sorcery
class SorceryCore < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string  :email, null: false, index: { unique: true }
      t.string  :crypted_password
      t.string  :salt
      t.string  :name

      t.string  :remember_me_token
      t.datetime :remember_me_token_expires_at
      t.index   :remember_me_token

      t.string  :reset_password_token
      t.datetime :reset_password_token_expires_at
      t.datetime :reset_password_email_sent_at
      t.integer :access_count_to_reset_password_page, default: 0
      t.index   :reset_password_token

      t.string   :activation_token
      t.datetime :activation_token_expires_at
      t.string   :activation_state, default: "pending"
      t.index    :activation_token

      t.timestamps
    end
  end
end

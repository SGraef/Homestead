# frozen_string_literal: true
# typed: false

class CreateLdapConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :ldap_connections do |t|
      t.references :household, null: false, foreign_key: true, index: { unique: true }
      t.string  :host, null: false
      t.integer :port
      t.string  :encryption, null: false, default: "start_tls"
      t.string  :base_dn, null: false
      t.string  :bind_dn
      t.text    :bind_password # Active Record encrypted
      t.string  :uid_attribute, null: false, default: "uid"
      t.string  :user_filter
      t.boolean :verify_tls, null: false, default: true
      t.string  :last_error, limit: 1000

      t.timestamps
    end
  end
end

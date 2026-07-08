# frozen_string_literal: true
# typed: false

class AddLdapUidToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :ldap_uid, :string
    add_index  :users, :ldap_uid, unique: true
  end
end

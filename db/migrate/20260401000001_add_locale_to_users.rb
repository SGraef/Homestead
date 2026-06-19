# frozen_string_literal: true

# Persist each user's chosen UI language so it follows them across sessions and
# devices instead of living only in the browser session. Nullable: a null means
# "not chosen yet", so we fall back to the session / Accept-Language / default.
class AddLocaleToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :locale, :string, limit: 5
  end
end

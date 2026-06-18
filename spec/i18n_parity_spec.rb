# frozen_string_literal: true
# typed: false

require "rails_helper"
require "i18n/tasks"

# Enforces de/en translation parity so a German-default feature can't ship a key
# that English is missing (which would leak the raw key to English users).
# Framework namespaces are excluded via config/i18n-tasks.yml (English resolves
# those from Rails defaults).
RSpec.describe "i18n parity" do # rubocop:disable RSpec/DescribeClass
  let(:i18n) { I18n::Tasks::BaseTask.new }

  it "has no missing app translations across de and en" do
    missing = i18n.missing_keys
    expect(missing).to be_empty, <<~MSG
      #{missing.leaves.count} missing i18n key(s):

      #{missing.inspect}

      Add the translations (or `bundle exec i18n-tasks add-missing`), then
      `bundle exec i18n-tasks normalize`.
    MSG
  end
end

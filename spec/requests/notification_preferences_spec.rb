# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Notification preferences" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  before do
    household
    login_via_post(user)
  end

  it "renders the settings form" do
    get notification_preference_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="notification_preference[enabled_kinds][]"')
  end

  it "saves reminder opt-outs and quiet hours" do
    patch notification_preference_path, params: { notification_preference: {
      enabled_kinds:     ["storage_expiring"], # storage_expired unchecked -> opted out
      quiet_hours_start: "22",
      quiet_hours_end:   "7"
    } }

    expect(response).to redirect_to(notification_preference_path)
    pref = user.reload.notification_preference
    expect(pref.allows?("storage_expiring")).to be(true)  # the checked kind stays on
    expect(pref.allows?("storage_expired")).to be(false)  # unchecked -> opted out
    expect(pref.quiet_hours_start).to eq(22)
    expect(pref.quiet_hours_end).to eq(7)
  end

  it "treats blank quiet hours as off and no checkboxes as all-opted-out" do
    patch notification_preference_path, params: { notification_preference: {
      quiet_hours_start: "",
      quiet_hours_end:   ""
    } }

    pref = user.reload.notification_preference
    expect(pref.quiet_hours_start).to be_nil
    expect(pref.disabled_kinds).to match_array(Notification::REMINDER_KINDS)
  end

  it "ignores a forged kind not in the reminder set" do
    patch notification_preference_path, params: { notification_preference: {
      enabled_kinds: %w[storage_expiring assigned bogus]
    } }

    pref = user.reload.notification_preference
    # The one real checked reminder kind stays on; the forged/interpersonal kinds
    # never enter disabled_kinds (only real reminder kinds can).
    expect(pref.allows?("storage_expiring")).to be(true)
    expect(pref.disabled_kinds).to match_array(Notification::REMINDER_KINDS - %w[storage_expiring])
    expect(pref.disabled_kinds).not_to include("assigned", "bogus")
  end
end

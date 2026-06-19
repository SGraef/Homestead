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
    expect(pref.disabled_kinds).to eq(["storage_expired"])
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
    # Only storage_expired (a real reminder kind) ends up disabled; the bogus and
    # interpersonal kinds never enter disabled_kinds.
    expect(pref.disabled_kinds).to eq(["storage_expired"])
  end
end

# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Language as a user setting" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  before do
    household
    login_via_post(user)
  end

  it "persists an explicit ?locale switch to the user's account" do
    expect { get root_path, params: { locale: "en" } }
      .to change { user.reload.locale }.from(nil).to("en")
    expect(response.body).to include('<html lang="en"')
  end

  it "renders in the user's saved language on later requests with no param" do
    user.update_column(:locale, "en")
    get root_path
    expect(response.body).to include('<html lang="en"')
  end

  it "lets a fresh switch override a previously saved preference" do
    user.update_column(:locale, "en")
    expect { get root_path, params: { locale: "de" } }
      .to change { user.reload.locale }.from("en").to("de")
  end

  it "ignores an unavailable locale and saves nothing" do
    get root_path, params: { locale: "fr" }
    expect(user.reload.locale).to be_nil
    expect(response.body).to include('<html lang="de"')
  end

  it "rejects an invalid locale on the model" do
    user.locale = "fr"
    expect(user).not_to be_valid
    expect(user.errors[:locale]).to be_present
  end
end

# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Inbound email sources" do
  let(:owner)        { create(:user) }
  let(:other_member) { create(:user) }
  let!(:household)   { create(:household, admin: owner) }

  before do
    household.users << other_member unless household.users.include?(other_member)
  end

  describe "GET /households/inbound_emails" do
    it "renders the index (the literal path beats /households/:id)" do
      login_via_post(owner)
      get "/households/inbound_emails"
      # The bug we just fixed routed this to households#show with
      # id="inbound_emails", which raised RecordNotFound -> 404.
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("inbound_email.title"))
    end
  end

  describe "ownership scoping" do
    let!(:source) do
      InboundEmailSource.create!(
        household: household, user: owner,
        label: "Mail", imap_host: "imap.x.tld",
        imap_username: "user", imap_password: "pw"
      )
    end

    it "lets the owner edit" do
      login_via_post(owner)
      get edit_inbound_email_source_path(source)
      expect(response).to have_http_status(:ok)
    end

    it "redirects non-owners away from edit with a flash" do
      login_via_post(other_member)
      get edit_inbound_email_source_path(source)
      expect(response).to redirect_to(inbound_email_sources_path)
      expect(flash[:alert]).to be_present
    end

    it "non-owners cannot delete" do
      login_via_post(other_member)
      expect {
        delete inbound_email_source_path(source)
      }.not_to change(InboundEmailSource, :count)
    end
  end
end

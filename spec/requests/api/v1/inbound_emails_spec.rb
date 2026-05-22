# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "API v1 Inbound emails" do
  let(:user)      { create(:user) }
  let!(:household) { create(:household, admin: user) }
  let!(:source) do
    InboundEmailSource.create!(
      household: household, user: user,
      label: "Personal", imap_host: "imap.example.com",
      imap_username: "rx@example.com", imap_password: "pw",
      folder: "INBOX"
    )
  end

  describe "GET /api/v1/inbound_emails" do
    it "lists the caller's sources" do
      get "/api/v1/inbound_emails", headers: api_login(user)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(1)
      expect(body.first).to include(
        "id"            => source.id,
        "label"         => "Personal",
        "imap_username" => "rx@example.com"
      )
      expect(body.first.keys).not_to include("imap_password")
    end

    it "rejects unauthenticated callers" do
      get "/api/v1/inbound_emails"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/inbound_emails/poll" do
    it "synchronously drains every owned source and returns counts" do
      result = InboundReceipts::ImapPoller::Result.new(
        sources: 1, scanned: 3, created: 2, skipped: 1, errors: 0
      )
      expect_any_instance_of(InboundReceipts::ImapPoller)
        .to receive(:call_for).with([source]).and_return(result)

      post "/api/v1/inbound_emails/poll", headers: api_login(user)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include(
        "sources_polled" => 1,
        "scanned"        => 3,
        "created"        => 2,
        "errors"         => 0
      )
      expect(body["details"].first["id"]).to eq(source.id)
    end

    it "404s when the user has no sources" do
      InboundEmailSource.delete_all
      post "/api/v1/inbound_emails/poll", headers: api_login(user)
      expect(response).to have_http_status(:not_found)
    end

    it "enqueues + 202s when X-Async is set" do
      headers = api_login(user).merge("X-Async" => "1")
      expect {
        post "/api/v1/inbound_emails/poll", headers: headers
      }.to have_enqueued_job(PollInboundReceiptsJob).with(source_id: source.id)
      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)).to eq("enqueued" => 1)
    end
  end

  describe "POST /api/v1/inbound_emails/:id/poll" do
    it "drains only that one source" do
      other = InboundEmailSource.create!(
        household: household, user: user,
        label: "Other", imap_host: "imap.example.com",
        imap_username: "second@example.com", imap_password: "pw",
        folder: "INBOX"
      )
      result = InboundReceipts::ImapPoller::Result.new(
        sources: 1, scanned: 1, created: 1, skipped: 0, errors: 0
      )
      expect_any_instance_of(InboundReceipts::ImapPoller)
        .to receive(:call_for).with([source]).and_return(result)

      post "/api/v1/inbound_emails/#{source.id}/poll", headers: api_login(user)
      expect(response).to have_http_status(:ok)
      # `other` should NOT have been touched.
      expect(JSON.parse(response.body)["details"].first["id"]).to eq(source.id)
    end

    it "404s on someone else's source" do
      stranger = create(:user)
      other_source = InboundEmailSource.create!(
        household: household, user: stranger,
        label: "Not mine", imap_host: "imap.example.com",
        imap_username: "x@example.com", imap_password: "pw",
        folder: "INBOX"
      )
      post "/api/v1/inbound_emails/#{other_source.id}/poll", headers: api_login(user)
      expect(response).to have_http_status(:not_found)
    end
  end
end

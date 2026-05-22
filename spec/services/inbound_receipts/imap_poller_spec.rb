# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe InboundReceipts::ImapPoller do
  let(:user)      { create(:user, email: "demo@example.com") }
  let!(:household) { create(:household, admin: user) }

  # Minimal stand-in for Net::IMAP. We don't talk to a real server in
  # specs; instead we stub `Net::IMAP.new` to return one of these and
  # record the calls.
  class FakeImap
    attr_accessor :selected_folder, :stored, :expunged, :logged_out
    def initialize(messages: {}, search_results: [])
      @messages = messages       # uid => raw RFC822
      @search   = search_results
      @stored   = []
      @logged_out = false
    end
    def login(_user, _pass); end
    def select(folder)
      self.selected_folder = folder
    end
    def search(_criteria) = @search
    def fetch(uid, _attr)
      data = @messages.fetch(uid)
      # Wrap the hash in braces so Ruby doesn't mistake `"RFC822" => data`
      # for keyword args -- Struct.new(:attr).new accepts a positional hash,
      # not kwargs, on Ruby 3+.
      [Struct.new(:attr).new({ "RFC822" => data })]
    end
    def store(uid, op, flags) = @stored << [uid, op, flags]
    def expunge = self.expunged = true
    def logout = self.logged_out = true
    def disconnect; end
  end

  let(:env) do
    {
      "RECEIPT_IMAP_HOST"     => "imap.example.com",
      "RECEIPT_IMAP_USERNAME" => "rxpantria",
      "RECEIPT_IMAP_PASSWORD" => "secret"
    }
  end

  around do |ex|
    keep = env.keys.to_h { |k| [k, ENV[k]] }
    env.each { |k, v| ENV[k] = v }
    ex.run
    keep.each { |k, v| ENV[k] = v }
  end

  def make_mail(from:, body: "hello", files: [])
    # Build outside the DSL block so `files` (and `attachments` on the
    # mail itself) don't get shadowed by Mail's own methods.
    mail = Mail.new
    mail.from    = from
    mail.to      = "rxpantria@example.com"
    mail.subject = "Receipt"
    mail.body    = body
    files.each do |f|
      mail.add_file(filename: f[:name], content: f[:bytes])
      mail.parts.last.content_type = "#{f[:mime]}; name=\"#{f[:name]}\""
    end
    mail
  end

  it "creates a Receipt + enqueues OCR for a known sender with a JPEG attachment" do
    mail = make_mail(
      from: user.email,
      files: [{ name: "rewe.jpg", bytes: "fake-jpg-bytes", mime: "image/jpeg" }]
    )
    fake = FakeImap.new(messages: { "1" => mail.encoded }, search_results: ["1"])
    allow(Net::IMAP).to receive(:new).and_return(fake)

    expect {
      result = described_class.new.call
      expect(result.scanned).to eq(1)
      expect(result.created).to eq(1)
    }.to change(Receipt, :count).by(1)
     .and have_enqueued_job(ProcessReceiptJob)

    expect(fake.stored).to eq([["1", "+FLAGS", [:Seen]]])
    expect(Receipt.last).to have_attributes(status: "pending", household: household, user: user)
  end

  it "ignores mail from senders without a matching user" do
    mail = make_mail(
      from: "stranger@example.com",
      files: [{ name: "x.png", bytes: "x", mime: "image/png" }]
    )
    fake = FakeImap.new(messages: { "9" => mail.encoded }, search_results: ["9"])
    allow(Net::IMAP).to receive(:new).and_return(fake)

    expect { described_class.new.call }.not_to change(Receipt, :count)
    expect(fake.stored).to be_empty
  end

  it "no-ops when env vars aren't set" do
    %w[RECEIPT_IMAP_HOST RECEIPT_IMAP_USERNAME RECEIPT_IMAP_PASSWORD].each { |k| ENV[k] = nil }
    expect(described_class.new.call).to be_nil
  end
end

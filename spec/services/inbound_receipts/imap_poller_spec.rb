# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe InboundReceipts::ImapPoller do
  # A fake the spec installs in place of Net::IMAP. Records calls so we
  # can assert on the wiring (login args, fetched UIDs, store flags).
  class FakeImap
    attr_reader :selected_folder, :stored, :expunged, :logged_in_as
    def initialize(messages: {}, search_results: [])
      @messages = messages
      @search   = search_results
      @stored   = []
      @expunged = false
    end
    def login(user, password); @logged_in_as = [user, password]; end
    def select(folder); @selected_folder = folder; end
    def search(_criteria) = @search
    def fetch(uid, _attr)
      [Struct.new(:attr).new({ "RFC822" => @messages.fetch(uid) })]
    end
    def store(uid, op, flags); @stored << [uid, op, flags]; end
    def expunge; @expunged = true; end
    def logout; end
    def disconnect; end
  end

  let(:owner)         { create(:user, email: "owner@example.com") }
  let!(:household)    { create(:household, admin: owner) }

  let!(:source) do
    InboundEmailSource.create!(
      household:     household,
      user:          owner,
      label:         "Personal mailbox",
      imap_host:     "imap.example.com",
      imap_username: "receipts@household.tld",
      imap_password: "shh-very-secret",
      folder:        "INBOX/Receipts"
    )
  end

  def make_mail(from: "anyone@somewhere.com", file:)
    mail = Mail.new
    mail.from    = from
    mail.to      = "receipts@household.tld"
    mail.subject = "Receipt"
    mail.body    = "see attached"
    mail.add_file(filename: file[:name], content: file[:bytes])
    mail.parts.last.content_type = "#{file[:mime]}; name=\"#{file[:name]}\""
    mail
  end

  it "selects the source's folder and creates a Receipt for each attachment" do
    mail = make_mail(file: { name: "rewe.jpg", bytes: "fake-jpg", mime: "image/jpeg" })
    fake = FakeImap.new(messages: { "1" => mail.encoded }, search_results: ["1"])
    allow(Net::IMAP).to receive(:new).and_return(fake)

    expect { described_class.new.call }
      .to change(Receipt, :count).by(1)

    expect(fake.selected_folder).to eq("INBOX/Receipts")
    expect(fake.logged_in_as).to eq(["receipts@household.tld", "shh-very-secret"])
    expect(fake.stored).to eq([["1", "+FLAGS", [:Seen]]])

    r = Receipt.last
    expect(r).to have_attributes(status: "pending", user: owner, household: household)
  end

  it "credits receipts to the source's user even when the From: address doesn't match a User" do
    mail = make_mail(
      from: "stranger@somewhere.com",
      file: { name: "x.png", bytes: "x", mime: "image/png" }
    )
    fake = FakeImap.new(messages: { "1" => mail.encoded }, search_results: ["1"])
    allow(Net::IMAP).to receive(:new).and_return(fake)

    described_class.new.call

    expect(Receipt.last.user).to eq(owner)
  end

  it "writes last_polled_at on success" do
    fake = FakeImap.new(messages: {}, search_results: [])
    allow(Net::IMAP).to receive(:new).and_return(fake)

    described_class.new.call

    expect(source.reload.last_polled_at).to be_within(5.seconds).of(Time.current)
    expect(source.last_error).to be_nil
  end

  it "records last_error when the connection blows up and doesn't crash the run" do
    allow(Net::IMAP).to receive(:new).and_raise(Errno::ECONNREFUSED, "boom")

    result = described_class.new.call

    expect(result.errors).to be >= 1
    expect(source.reload.last_error).to include("ECONNREFUSED")
  end

  it "encrypts the password column at rest" do
    raw = ActiveRecord::Base.connection
                            .select_value("SELECT imap_password FROM inbound_email_sources WHERE id=#{source.id}")
    expect(raw).not_to include("shh-very-secret")
    expect(source.reload.imap_password).to eq("shh-very-secret")
  end

  it "no-ops cleanly with no sources" do
    InboundEmailSource.delete_all
    expect { described_class.new.call }.not_to raise_error
  end
end

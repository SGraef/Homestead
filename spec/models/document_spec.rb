# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Document do
  let(:household) { create(:household) }

  it "is valid with a title and an attached supported file" do
    expect(build(:document, household: household)).to be_valid
  end

  it "requires a title" do
    expect(build(:document, household: household, title: "")).not_to be_valid
  end

  it "requires an attached file on create" do
    doc = build(:document, household: household)
    doc.file.detach
    expect(doc).not_to be_valid
  end

  it "rejects an unsupported content type" do
    doc = build(:document, household: household)
    doc.file.attach(io: StringIO.new("x"), filename: "a.txt", content_type: "text/plain")
    expect(doc).not_to be_valid
  end

  describe "#paperless_linked?" do
    it "is true once a paperless document id is set" do
      expect(build(:document, paperless_document_id: 7)).to be_paperless_linked
      expect(build(:document, paperless_document_id: nil)).not_to be_paperless_linked
    end
  end

  describe "#paperless_tags_list" do
    it "splits the stored comma string" do
      doc = build(:document, paperless_tags: "Strom, Rechnung")
      expect(doc.paperless_tags_list).to eq(%w[Strom Rechnung])
    end

    it "is empty when nil" do
      expect(build(:document, paperless_tags: nil).paperless_tags_list).to eq([])
    end
  end
end

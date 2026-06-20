# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Paperless::Client do
  let(:connection) { build(:paperless_connection, base_url: "https://paperless.example.test", api_token: "tok-1") }
  let(:client)     { described_class.new(connection) }
  let(:base)       { "https://paperless.example.test" }
  let(:auth)       { { "Authorization" => "Token tok-1" } }

  describe "#ping" do
    it "succeeds on a 200" do
      stub_request(:get, "#{base}/api/").with(headers: auth).to_return(status: 200, body: "{}")
      expect { client.ping }.not_to raise_error
    end

    it "raises AuthError on 401" do
      stub_request(:get, "#{base}/api/").to_return(status: 401, body: "no")
      expect { client.ping }.to raise_error(Paperless::AuthError)
    end

    it "raises Error on 500" do
      stub_request(:get, "#{base}/api/").to_return(status: 500, body: "boom")
      expect { client.ping }.to raise_error(Paperless::Error)
    end
  end

  describe "#upload" do
    it "posts multipart and returns the task uuid" do
      stub = stub_request(:post, "#{base}/api/documents/post_document/")
             .with(headers: { "Authorization" => "Token tok-1" }) do |req|
               req.headers["Content-Type"].to_s.start_with?("multipart/form-data") &&
                 req.body.include?("name=\"document\"; filename=\"bill.pdf\"") &&
                 req.body.include?("name=\"title\"") &&
                 req.body.include?("name=\"tags\"")
             end
             .to_return(status: 200, body: '"task-uuid-9"')

      uuid = client.upload(io: StringIO.new("data"), filename: "bill.pdf", title: "Bill", tags: ["homestead"])
      expect(uuid).to eq("task-uuid-9")
      expect(stub).to have_been_requested
    end
  end

  describe "#task" do
    it "returns the first task record" do
      stub_request(:get, "#{base}/api/tasks/?task_id=abc")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: [{ status: "SUCCESS", related_document: 12 }].to_json)
      expect(client.task("abc")).to include("status" => "SUCCESS", "related_document" => 12)
    end

    it "returns nil when paperless knows nothing yet" do
      stub_request(:get, "#{base}/api/tasks/?task_id=abc").to_return(status: 200, body: "[]")
      expect(client.task("abc")).to be_nil
    end
  end

  describe "#document and name lookups" do
    it "reads the document and resolves names" do
      stub_request(:get, "#{base}/api/documents/12/")
        .to_return(status: 200, body: { document_type: 3, correspondent: 5, tags: [7, 8] }.to_json)
      stub_request(:get, "#{base}/api/document_types/3/").to_return(status: 200, body: { name: "Rechnung" }.to_json)
      stub_request(:get, "#{base}/api/correspondents/5/").to_return(status: 200, body: { name: "Stadtwerke" }.to_json)
      stub_request(:get, "#{base}/api/tags/7/").to_return(status: 200, body: { name: "Strom" }.to_json)

      doc = client.document(12)
      expect(client.document_type_name(doc["document_type"])).to eq("Rechnung")
      expect(client.correspondent_name(doc["correspondent"])).to eq("Stadtwerke")
      expect(client.tag_name(doc["tags"].first)).to eq("Strom")
    end

    it "returns nil for a name lookup that 404s" do
      stub_request(:get, "#{base}/api/tags/99/").to_return(status: 404, body: "{}")
      expect(client.tag_name(99)).to be_nil
    end
  end

  describe "transport errors" do
    it "wraps connection failures in Paperless::Error" do
      stub_request(:get, "#{base}/api/").to_raise(Errno::ECONNREFUSED)
      expect { client.ping }.to raise_error(Paperless::Error)
    end
  end
end

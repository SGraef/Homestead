# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe PaperlessPushJob do
  let(:household) { create(:household) }
  let(:document)  { create(:document, household: household) }
  let(:client)    { instance_double(Paperless::Client) }

  before { allow(Paperless::Client).to receive(:new).and_return(client) }

  context "without a paperless connection" do
    it "is a no-op and leaves the document stored" do
      expect(Paperless::Client).not_to receive(:new)
      described_class.perform_now(document.id)
      expect(document.reload.status).to eq("stored")
    end
  end

  context "with a connection" do
    let!(:connection) { create(:paperless_connection, household: household) }

    describe "upload phase" do
      it "uploads, stores the task uuid and enqueues a poll" do
        allow(client).to receive(:upload).and_return("task-uuid-1")

        expect do
          described_class.perform_now(document.id)
        end.to have_enqueued_job(described_class).with(document.id, poll: 1)

        document.reload
        expect(document.status).to eq("pending")
        expect(document.paperless_task_uuid).to eq("task-uuid-1")
      end
    end

    describe "poll phase" do
      before { document.update!(status: "pending", paperless_task_uuid: "task-uuid-1") }

      it "finalizes on SUCCESS and mirrors + matches the classification" do
        cat = household.offer_categories.create!(name: "Energie", position: 0)
        cat.offer_category_keywords.create!(keyword: "stadtwerke")

        allow(client).to receive(:task).with("task-uuid-1")
                                       .and_return("status" => "SUCCESS", "related_document" => 12)
        allow(client).to receive(:document).with(12)
                                           .and_return("document_type" => 3, "correspondent" => 5, "tags" => [7])
        allow(client).to receive(:document_type_name).with(3).and_return("Stromrechnung")
        allow(client).to receive(:correspondent_name).with(5).and_return("Stadtwerke")
        allow(client).to receive(:tag_name).with(7).and_return("Strom")

        described_class.perform_now(document.id)

        document.reload
        expect(document.status).to eq("synced")
        expect(document.paperless_document_id).to eq(12)
        expect(document.paperless_document_type).to eq("Stromrechnung")
        expect(document.paperless_correspondent).to eq("Stadtwerke")
        expect(document.paperless_tags).to eq("Strom")
        expect(document.matched_category).to eq("Energie")
        expect(connection.reload.last_synced_at).to be_present
      end

      it "marks the document failed on FAILURE" do
        allow(client).to receive(:task).and_return("status" => "FAILURE", "result" => "boom")
        described_class.perform_now(document.id)
        expect(document.reload.status).to eq("failed")
        expect(document.error_message).to include("boom")
      end

      it "re-enqueues while the task is still pending" do
        allow(client).to receive(:task).and_return("status" => "PENDING")
        expect do
          described_class.perform_now(document.id, poll: 1)
        end.to have_enqueued_job(described_class).with(document.id, poll: 2)
        expect(document.reload.status).to eq("pending")
      end

      it "gives up after the poll budget is exhausted" do
        allow(client).to receive(:task).and_return("status" => "PENDING")
        described_class.perform_now(document.id, poll: described_class::MAX_POLLS)
        expect(document.reload.status).to eq("failed")
      end

      it "flags a success with no document id as a possible duplicate" do
        allow(client).to receive(:task).and_return("status" => "SUCCESS", "related_document" => nil)
        described_class.perform_now(document.id)
        expect(document.reload.status).to eq("failed")
        expect(document.error_message).to include("duplicate")
      end
    end

    describe "transport failure" do
      it "records the error and marks the document failed" do
        allow(client).to receive(:upload).and_raise(Paperless::Error, "host down")
        described_class.perform_now(document.id)
        expect(document.reload.status).to eq("failed")
        expect(connection.reload.last_error).to include("host down")
      end
    end
  end
end

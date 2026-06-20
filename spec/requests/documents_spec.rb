# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Documents" do
  let(:user)       { create(:user) }
  let!(:household) { create(:household, admin: user) }

  before { login_via_post(user) }

  def pdf_upload
    Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 fake"), "application/pdf", original_filename: "bill.pdf")
  end

  describe "GET /documents" do
    it "lists documents" do
      create(:document, household: household, title: "Internetrechnung")
      get documents_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Internetrechnung")
    end
  end

  describe "GET /documents/new" do
    it "renders the upload form" do
      get new_document_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /documents/:id" do
    it "renders a synced document with its paperless link" do
      create(:paperless_connection, household: household, base_url: "https://p.lan")
      doc = create(:document, household: household, status: "synced", paperless_document_id: 12,
                              paperless_document_type: "Rechnung", matched_category: "Energie",
                              paperless_tags: "Strom, Rechnung")
      get document_path(doc)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("https://p.lan/documents/12/")
    end
  end

  describe "POST /documents" do
    it "stores a local-only document when paperless is not configured" do
      expect do
        post documents_path, params: { document: { title: "Versicherung", file: pdf_upload } }
      end.to change(Document, :count).by(1)
      doc = Document.last
      expect(doc.status).to eq("stored")
      expect(response).to redirect_to(doc)
    end

    it "enqueues due-date processing for a non-receipt document" do
      expect do
        post documents_path, params: { document: { title: "Stromrechnung", kind: "bill", file: pdf_upload } }
      end.to have_enqueued_job(ProcessDocumentJob)
    end

    it "does not enqueue due-date processing for a receipt" do
      expect do
        post documents_path, params: { document: { title: "Kassenbon", kind: "receipt", file: pdf_upload } }
      end.not_to have_enqueued_job(ProcessDocumentJob)
    end

    it "enqueues a paperless push when connected" do
      create(:paperless_connection, household: household)
      expect do
        post documents_path, params: { document: { title: "Stromrechnung", file: pdf_upload } }
      end.to have_enqueued_job(PaperlessPushJob)
      expect(Document.last.status).to eq("pending")
    end

    it "re-renders on a missing file" do
      post documents_path, params: { document: { title: "No file" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /documents/:id/sync" do
    it "is rejected when no connection is configured" do
      doc = create(:document, household: household)
      post sync_document_path(doc)
      expect(response).to redirect_to(doc)
      expect(flash[:alert]).to be_present
    end

    it "re-enqueues a push when connected and not yet linked" do
      create(:paperless_connection, household: household)
      doc = create(:document, household: household)
      expect do
        post sync_document_path(doc)
      end.to have_enqueued_job(PaperlessPushJob).with(doc.id)
      expect(doc.reload.status).to eq("pending")
    end
  end

  describe "DELETE /documents/:id" do
    it "removes the document" do
      doc = create(:document, household: household)
      expect { delete document_path(doc) }.to change(Document, :count).by(-1)
    end
  end
end

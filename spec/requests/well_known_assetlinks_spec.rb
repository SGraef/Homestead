# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "GET /.well-known/assetlinks.json" do
  it "responds with the Digital Asset Links shape Chrome expects" do
    get "/.well-known/assetlinks.json"
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with("application/json")

    body = JSON.parse(response.body)
    expect(body).to be_an(Array)
    expect(body.first).to include(
      "relation" => ["delegate_permission/common.handle_all_urls"]
    )
    expect(body.first["target"]).to include("namespace" => "android_app")
  end

  it "exposes the configured package name + fingerprints" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ANDROID_TWA_PACKAGE", anything)
                                 .and_return("de.example.test")
    allow(ENV).to receive(:fetch).with("ANDROID_TWA_FINGERPRINTS", anything)
                                 .and_return("AA:BB:CC, DD:EE:FF")

    get "/.well-known/assetlinks.json"
    body = JSON.parse(response.body)
    target = body.first["target"]
    expect(target["package_name"]).to eq("de.example.test")
    expect(target["sha256_cert_fingerprints"]).to eq(["AA:BB:CC", "DD:EE:FF"])
  end

  it "is reachable without a logged-in session" do
    get "/.well-known/assetlinks.json"
    expect(response).to have_http_status(:ok) # not a 302 to /login
  end
end

# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Maintenance::Backup do
  let(:root)         { Dir.mktmpdir("hs-backup") }
  let(:storage_root) { Dir.mktmpdir("hs-storage") }
  let(:ok)           { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failed)       { instance_double(Process::Status, success?: false, exitstatus: 2) }

  after do
    FileUtils.remove_entry(root)
    FileUtils.remove_entry(storage_root)
  end

  before do
    File.write(File.join(storage_root, "blobfile"), "blob-bytes")
    # Plain double (ActiveStorage's DiskService constant is loaded lazily and
    # isn't available to instance_double in the test env). The guard only calls
    # #root + #respond_to?(:root) on it.
    disk = double("DiskService", root: storage_root)
    allow(ActiveStorage::Blob).to receive(:service).and_return(disk)
  end

  it "writes the mysqldump output and copies the Active Storage blobs" do
    allow(Open3).to receive(:capture3).and_return(["-- dump --\n", "", ok])

    dir = described_class.call(root: root, timestamp: "20260101-000000")

    expect(dir.to_s).to eq(File.join(root, "20260101-000000"))
    expect(File.read(dir.join("database.sql"))).to eq("-- dump --\n")
    expect(File.read(dir.join("active_storage", "blobfile"))).to eq("blob-bytes")
  end

  it "passes the DB password via MYSQL_PWD env, never on argv" do
    captured_env = nil
    captured_args = nil
    allow(Open3).to receive(:capture3) do |env, *args|
      captured_env  = env
      captured_args = args
      ["dump", "", ok]
    end

    described_class.call(root: root, timestamp: "t")

    expect(captured_env).to have_key("MYSQL_PWD")
    expect(captured_args.first).to eq("mysqldump")
    expect(captured_args.join(" ")).not_to include("--password")
  end

  it "raises Backup::Error when mysqldump fails" do
    allow(Open3).to receive(:capture3).and_return(["", "Access denied", failed])

    expect { described_class.call(root: root, timestamp: "t") }
      .to raise_error(Maintenance::Backup::Error, /mysqldump failed/)
  end

  it "raises a clear error when mysqldump is not installed" do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

    expect { described_class.call(root: root, timestamp: "t") }
      .to raise_error(Maintenance::Backup::Error, /mysqldump not found/)
  end

  it "skips the Active Storage copy when the service has no local root (e.g. S3)" do
    allow(ActiveStorage::Blob).to receive(:service).and_return(double("S3Service"))
    allow(Open3).to receive(:capture3).and_return(["dump", "", ok])

    dir = described_class.call(root: root, timestamp: "t")

    expect(File.exist?(dir.join("database.sql"))).to be(true)
    expect(Dir.exist?(dir.join("active_storage"))).to be(false)
  end
end

# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe SafeHttp do
  # The guard is disabled in the test env by default (it can't do real DNS under
  # WebMock); enable it for these examples and stub the resolver so we never hit
  # the network.
  around do |example|
    previous = described_class.enabled
    described_class.enabled = true
    example.run
  ensure
    described_class.enabled = previous
  end

  def stub_resolve(host, *addresses)
    allow(described_class).to receive(:resolve).and_call_original
    allow(described_class).to receive(:resolve).with(host).and_return(addresses)
  end

  describe ".validate_uri!" do
    it "allows a host that resolves to a public address" do
      stub_resolve("example.com", "93.184.216.34")
      expect(described_class.validate_uri!("https://example.com/feed")).to be_a(URI::Generic)
    end

    it "blocks non-http(s) schemes" do
      %w[file:///etc/passwd ftp://host/x gopher://h/_ ldap://h].each do |u|
        expect { described_class.validate_uri!(u) }
          .to raise_error(SafeHttp::BlockedRequestError, /scheme/)
      end
    end

    it "blocks loopback, private, link-local and reserved IP literals" do
      %w[
        http://127.0.0.1/ http://127.0.0.1:9200/ http://10.0.0.5/
        http://192.168.1.1/ http://172.16.5.5/ http://169.254.169.254/latest/meta-data
        http://0.0.0.0/ http://100.64.0.1/ http://[::1]/ http://[fc00::1]/
        http://[fe80::1]/ http://255.255.255.255/
      ].each do |u|
        expect { described_class.validate_uri!(u) }
          .to raise_error(SafeHttp::BlockedRequestError), "expected #{u} to be blocked"
      end
    end

    it "blocks IPv4-mapped IPv6 loopback" do
      expect { described_class.validate_uri!("http://[::ffff:127.0.0.1]/") }
        .to raise_error(SafeHttp::BlockedRequestError)
    end

    it "blocks a hostname that resolves to a private address (DNS-based SSRF)" do
      stub_resolve("evil.example.com", "10.1.2.3")
      expect { described_class.validate_uri!("https://evil.example.com/") }
        .to raise_error(SafeHttp::BlockedRequestError, /blocked address/)
    end

    it "blocks when ANY resolved address is private (mixed A records)" do
      stub_resolve("rebind.example.com", "93.184.216.34", "127.0.0.1")
      expect { described_class.validate_uri!("https://rebind.example.com/") }
        .to raise_error(SafeHttp::BlockedRequestError)
    end

    it "blocks an unresolvable host" do
      stub_resolve("nope.invalid")
      expect { described_class.validate_uri!("https://nope.invalid/") }
        .to raise_error(SafeHttp::BlockedRequestError, /could not resolve/)
    end

    it "is a no-op when disabled (test default)" do
      described_class.enabled = false
      expect(described_class.validate_uri!("http://127.0.0.1/")).to be_a(URI::Generic)
    end
  end

  describe ".blocked_address?" do
    it "permits well-known public addresses" do
      expect(described_class.blocked_address?("93.184.216.34")).to be(false)
      expect(described_class.blocked_address?("1.1.1.1")).to be(false)
      expect(described_class.blocked_address?("2606:4700:4700::1111")).to be(false)
    end

    it "fails closed on an unparseable address" do
      expect(described_class.blocked_address?("not-an-ip")).to be(true)
    end
  end
end

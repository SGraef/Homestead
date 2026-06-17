# frozen_string_literal: true
# typed: false

require "ipaddr"
require "socket"

# SSRF guard for outbound HTTP. Homestead fetches from several external sources
# (offer feeds, barcode lookup, recipe import, Bring!, Google Calendar) and one
# of them (barcode lookup) follows redirects. Without a guard, a malicious feed
# response or redirect could point a request at an internal host
# (http://192.168.x, http://[::1]) or the cloud metadata endpoint
# (169.254.169.254) and exfiltrate secrets — server-side request forgery.
#
# `validate_uri!` is called before every Net::HTTP connection (including each
# redirect hop). It rejects non-http(s) schemes and any host that resolves to a
# loopback / private / link-local / reserved address.
#
# Disabled in the test environment because resolving real hostnames can't hit
# the network under WebMock; the classification logic is covered directly in
# spec/services/safe_http_spec.rb (with the guard explicitly enabled + a stubbed
# resolver). Production and development run with it on.
#
# Note: this is resolve-then-connect, so a determined DNS-rebinding attacker
# could in theory flip the record between our check and Net::HTTP's own
# resolution. Pinning the connection to the validated IP is a future hardening
# step; blocking the static + first-resolution cases already closes the
# overwhelming majority of the SSRF surface (fixed-host feeds + redirects).
module SafeHttp
  class BlockedRequestError < StandardError; end

  ALLOWED_SCHEMES = %w[http https].freeze

  # IPv4 + IPv6 ranges that must never be reachable from an outbound fetch:
  # this-network, RFC1918 private, CGNAT, loopback, link-local (incl. cloud
  # metadata 169.254.169.254), IETF-reserved, documentation, multicast,
  # unique-local and site-local IPv6.
  BLOCKED_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15
    198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 255.255.255.255/32
    ::1/128 ::/128 64:ff9b::/96 100::/64 2001:db8::/32 fc00::/7 fe80::/10
    fec0::/10 ff00::/8
  ].map { |cidr| IPAddr.new(cidr) }.freeze

  class << self
    attr_accessor :enabled
  end
  self.enabled = !Rails.env.test?

  # Returns the parsed URI when safe; raises BlockedRequestError otherwise.
  def self.validate_uri!(uri)
    uri = URI.parse(uri.to_s) unless uri.is_a?(URI::Generic)
    return uri unless enabled

    raise BlockedRequestError, "blocked scheme: #{uri.scheme.inspect}" unless ALLOWED_SCHEMES.include?(uri.scheme)

    # #hostname (not #host) strips the brackets from IPv6 literals so they
    # classify correctly (URI#host would yield "[::1]").
    host = uri.hostname.to_s
    raise BlockedRequestError, "missing host in #{uri}" if host.empty?

    addresses = resolve(host)
    raise BlockedRequestError, "could not resolve host: #{host}" if addresses.empty?

    blocked = addresses.find { |ip| blocked_address?(ip) }
    raise BlockedRequestError, "#{host} resolves to blocked address #{blocked}" if blocked

    uri
  end

  # Resolve a hostname to its IP strings via the system resolver (so /etc/hosts
  # and both address families are honoured, matching what Net::HTTP will use).
  # An IP literal is returned as-is (no DNS).
  def self.resolve(host)
    return [host] if ip_literal?(host)

    Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
  rescue SocketError
    []
  end

  def self.ip_literal?(host)
    IPAddr.new(host)
    true
  rescue IPAddr::Error
    false
  end

  # True if the address falls in any blocked range. IPv4-mapped IPv6
  # (::ffff:127.0.0.1) is folded to its native IPv4 first. Anything unparseable
  # is treated as blocked (fail closed).
  def self.blocked_address?(ip)
    addr = IPAddr.new(ip.to_s.split("%").first)
    addr = addr.native if addr.ipv4_mapped?
    BLOCKED_RANGES.any? { |range| range.include?(addr) }
  rescue IPAddr::Error
    true
  end
end

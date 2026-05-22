# frozen_string_literal: true
# typed: false

require "net/imap"
require "mail"

module InboundReceipts
  # Polls a configured IMAP mailbox for unread mail, turns each
  # supported attachment into a Receipt (one per attachment),
  # enqueues ProcessReceiptJob, and marks the message Seen so it
  # isn't picked up next tick.
  #
  # Mapping email -> household:
  # The sender's address must match a known User.email; the receipt is
  # filed under that user's default_household. This means forwarding
  # only works from an address the recipient has registered with
  # Pantria -- the most common case for a personal Unraid install.
  #
  # Configuration (all env-driven, all optional so the job no-ops in
  # environments that haven't set anything up):
  #
  #   RECEIPT_IMAP_HOST       e.g. "imap.fastmail.com"
  #   RECEIPT_IMAP_PORT       default 993
  #   RECEIPT_IMAP_SSL        "true" (default) / "false"
  #   RECEIPT_IMAP_USERNAME
  #   RECEIPT_IMAP_PASSWORD
  #   RECEIPT_IMAP_FOLDER     default "INBOX"
  #   RECEIPT_IMAP_EXPUNGE    "true" deletes processed mail, "false"
  #                           (default) just flags it \Seen
  class ImapPoller
    Result = Struct.new(:scanned, :created, :skipped, :errors, keyword_init: true) do
      def to_s = "scanned=#{scanned} created=#{created} skipped=#{skipped} errors=#{errors}"
    end

    DEFAULT_FOLDER  = "INBOX"
    DEFAULT_PORT    = 993
    SEARCH_CRITERIA = %w[UNSEEN].freeze

    def initialize(host: nil, port: nil, ssl: nil, username: nil, password: nil,
                   folder: nil, expunge: nil)
      @host     = (host     || ENV["RECEIPT_IMAP_HOST"]).to_s
      @port     = (port     || ENV["RECEIPT_IMAP_PORT"] || DEFAULT_PORT).to_i
      @ssl      = ssl.nil?  ? ENV.fetch("RECEIPT_IMAP_SSL", "true") != "false" : !!ssl
      @username = (username || ENV["RECEIPT_IMAP_USERNAME"]).to_s
      @password = (password || ENV["RECEIPT_IMAP_PASSWORD"]).to_s
      @folder   = (folder   || ENV["RECEIPT_IMAP_FOLDER"] || DEFAULT_FOLDER).to_s
      @expunge  = expunge.nil? ? ENV["RECEIPT_IMAP_EXPUNGE"] == "true" : !!expunge
    end

    # @return [Result, nil] nil when not configured.
    def call
      return nil unless configured?

      scanned = created = skipped = errors = 0

      imap = open_connection
      begin
        imap.select(@folder)
        message_ids = imap.search(SEARCH_CRITERIA)

        message_ids.each do |uid|
          scanned += 1
          begin
            raw   = imap.fetch(uid, "RFC822").first.attr["RFC822"]
            mail  = Mail.read_from_string(raw)
            built = process_message(mail)
            if built.positive?
              created += built
              flag_message(imap, uid)
            else
              skipped += 1
            end
          rescue StandardError => e
            errors += 1
            Rails.logger.warn("[InboundReceipts] message uid=#{uid} failed: #{e.class}: #{e.message}")
          end
        end

        imap.expunge if @expunge && created.positive?
      ensure
        safe_logout(imap)
      end

      Result.new(scanned: scanned, created: created, skipped: skipped, errors: errors)
    end

    private

    def configured?
      [@host, @username, @password].none?(&:empty?)
    end

    def open_connection
      Net::IMAP.new(@host, port: @port, ssl: @ssl).tap do |imap|
        imap.login(@username, @password)
      end
    end

    # @return [Integer] number of receipts created from this message
    def process_message(mail)
      sender = Array(mail.from).first.to_s.downcase
      return 0 if sender.empty?

      user = User.find_by("LOWER(email) = ?", sender)
      unless user
        Rails.logger.info("[InboundReceipts] dropping mail from #{sender.inspect} — no matching user")
        return 0
      end

      household = user.default_household
      unless household
        Rails.logger.info("[InboundReceipts] user #{user.id} has no household — skipping")
        return 0
      end

      attachments = supported_attachments(mail)
      return 0 if attachments.empty?

      created = 0
      attachments.each do |part|
        Receipt.transaction do
          receipt = household.receipts.build(user: user, status: "pending")
          receipt.image.attach(
            io:           StringIO.new(part.body.decoded),
            filename:     attachment_filename(part),
            content_type: part.mime_type
          )
          receipt.save!
          ProcessReceiptJob.perform_later(receipt.id)
          created += 1
        end
      end
      created
    end

    def supported_attachments(mail)
      mail.all_parts.select do |part|
        part.attachment? && Receipt::ACCEPTED_MIME_TYPES.include?(part.mime_type.to_s)
      end
    end

    def attachment_filename(part)
      part.filename.presence || "receipt-#{SecureRandom.hex(4)}"
    end

    def flag_message(imap, uid)
      imap.store(uid, "+FLAGS", [:Seen])
    end

    def safe_logout(imap)
      imap.logout
    rescue StandardError
      # already disconnected; nothing to do
    ensure
      imap.disconnect rescue nil
    end
  end
end

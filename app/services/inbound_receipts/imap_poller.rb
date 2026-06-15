# frozen_string_literal: true
# typed: false

require "net/imap"
require "mail"

module InboundReceipts
  # Drains every configured {InboundEmailSource} into pending Receipt
  # rows + a ProcessReceiptJob per attachment.
  #
  # Sources are managed in the UI (one per (user, household)), so this
  # service takes no env vars. It loops over each source, opens that
  # mailbox's IMAP connection with its own credentials, polls the
  # configured folder, and credits each created Receipt to the
  # source's owning user and household.
  #
  # Per-source last_polled_at and last_error are written back on each
  # tick so the UI can surface health.
  class ImapPoller
    Result = Struct.new(:sources, :scanned, :created, :skipped, :errors, keyword_init: true) do
      def to_s
        "sources=#{sources} scanned=#{scanned} created=#{created} " \
          "skipped=#{skipped} errors=#{errors}"
      end
    end

    SEARCH_CRITERIA = %w[UNSEEN].freeze

    # Drain every configured source for the single household. Scoped to
    # {Household.current} so a database upgraded from the old multi-household
    # schema never polls orphaned households' inboxes.
    # @return [Result]
    def call
      household = Household.current
      sources = household ? household.inbound_email_sources.includes(:user, :household).to_a : []
      call_for(sources)
    end

    # Drain a specific subset (used by the API trigger).
    # @param sources [Array<InboundEmailSource>]
    # @return [Result]
    def call_for(sources)
      stats = { sources: sources.size, scanned: 0, created: 0, skipped: 0, errors: 0 }
      sources.each { |s| drain(s, stats) }
      Result.new(**stats)
    end

    private

    def drain(source, stats)
      imap = open_connection(source)
      begin
        imap.select(source.folder)
        uids = imap.search(SEARCH_CRITERIA)

        uids.each do |uid|
          stats[:scanned] += 1
          begin
            raw   = imap.fetch(uid, "RFC822").first.attr["RFC822"]
            mail  = Mail.read_from_string(raw)
            built = process_message(mail, source)
            if built.positive?
              stats[:created] += built
              imap.store(uid, "+FLAGS", [:Seen])
            else
              stats[:skipped] += 1
            end
          rescue StandardError => e
            stats[:errors] += 1
            Rails.logger.warn("[InboundReceipts] source=#{source.id} uid=#{uid} " \
                              "failed: #{e.class}: #{e.message}")
          end
        end

        imap.expunge if source.expunge && stats[:created].positive?
        source.update_columns(last_polled_at: Time.current, last_error: nil)
      ensure
        safe_logout(imap)
      end
    rescue StandardError => e
      stats[:errors] += 1
      source.update_columns(last_polled_at: Time.current,
                            last_error:     "#{e.class}: #{e.message}".first(1000))
      Rails.logger.warn("[InboundReceipts] source=#{source.id} #{source.label.inspect} " \
                        "drain failed: #{e.class}: #{e.message}")
    end

    def open_connection(source)
      Net::IMAP.new(source.imap_host, port: source.imap_port, ssl: source.imap_ssl).tap do |imap|
        imap.login(source.imap_username, source.imap_password)
      end
    end

    # @return [Integer] number of receipts created from this message
    def process_message(mail, source)
      attachments = supported_attachments(mail)
      return 0 if attachments.empty?

      created = 0
      attachments.each do |part|
        Receipt.transaction do
          receipt = source.household.receipts.build(user: source.user, status: "pending")
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

    def safe_logout(imap)
      imap.logout
    rescue StandardError
      # already disconnected; nothing to do
    ensure
      begin
        imap.disconnect
      rescue StandardError
        nil
      end
    end
  end
end

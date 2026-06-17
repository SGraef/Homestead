# frozen_string_literal: true
# typed: false

# REST API for triggering inbound-mailbox drains from outside Homestead
# (n8n, Home Assistant, cron on another box, …). Synchronous so the
# caller gets per-source counts back in the response -- handy for an
# n8n flow that wants to react to "X new receipts arrived".
#
# Auth: Bearer token like every other /api/v1/* endpoint.
# Scope: only sources owned by the token's user are touched. The
# household-id header isn't required (a token can drain mailboxes
# across every household the user is in), but supplying it scopes
# the action to that household for safety.
module Api
  module V1
    class InboundEmailsController < BaseController
      # GET /api/v1/inbound_emails
      def index
        sources = scoped_sources.ordered
        render json: sources.map { |s| serialize(s) }
      end

      # POST /api/v1/inbound_emails/poll
      # POST /api/v1/inbound_emails/:id/poll
      def poll
        targets = params[:id].present? ? Array(find_owned(params[:id])) : scoped_sources.to_a

        if targets.empty?
          render_error(:not_found, "No inbound mailboxes configured")
          return
        end

        # Synchronous drain so n8n can branch on the result. If a
        # source's IMAP server is slow this blocks the HTTP request;
        # set X-Async: 1 to enqueue instead and get a 202 back.
        if request.headers["X-Async"] == "1"
          targets.each { |t| PollInboundReceiptsJob.perform_later(source_id: t.id) }
          render json: { enqueued: targets.size }, status: :accepted
        else
          stats = InboundReceipts::ImapPoller.new.call_for(targets)
          render json: {
            sources_polled: stats.sources,
            scanned:        stats.scanned,
            created:        stats.created,
            skipped:        stats.skipped,
            errors:         stats.errors,
            details:        targets.map { |t| serialize(t.reload) }
          }
        end
      end

      private

      def scoped_sources
        InboundEmailSource.where(user: @current_user, household: @current_household)
      end

      def find_owned(id)
        scoped_sources.find_by(id: id) || (raise ActiveRecord::RecordNotFound)
      end

      def serialize(source)
        {
          id:             source.id,
          label:          source.label,
          household_id:   source.household_id,
          imap_host:      source.imap_host,
          imap_username:  source.imap_username,
          folder:         source.folder,
          last_polled_at: source.last_polled_at&.iso8601,
          last_error:     source.last_error
        }
      end
    end
  end
end

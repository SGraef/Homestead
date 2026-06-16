# frozen_string_literal: true
# typed: false

module CalendarSync
  # Pulls remote changes into local CalendarEvents (remote -> local). Incremental
  # via the stored syncToken; a 410 (expired token) triggers a bounded full
  # re-sync. Cancelled items are deletes. All writes run inside the echo guard
  # (so the PR4 push-back hooks don't re-send them) and the household timezone
  # (so all-day DATE values land on the right local day).
  class Pull
    def initialize(connection)
      @connection = connection
      @client     = Google::ApiClient.new(connection)
    end

    def call
      return false unless @connection.connected? && @connection.calendar_id.present?

      Time.use_zone(@connection.household.timezone) do
        CalendarEvent.without_sync { sync }
      end
      @connection.update!(last_synced_at: Time.current, status: "connected", last_error_code: nil)
      true
    rescue Google::Error
      @connection.update(status: "error", last_error_code: "pull")
      false
    end

    private

    def sync
      run(@connection.sync_token)
    rescue Google::InvalidSyncToken
      @connection.update!(sync_token: nil)
      run(nil)
    end

    def run(token)
      page = nil
      next_sync = nil
      loop do
        result = @client.list_events(@connection.calendar_id, sync_token: token, page_token: page)
        apply(result["items"] || [])
        next_sync = result["nextSyncToken"] if result["nextSyncToken"].present?
        page = result["nextPageToken"]
        break if page.blank?
      end
      @connection.update!(sync_token: next_sync) if next_sync.present?
    end

    def apply(items)
      items.each do |item|
        if item["status"] == "cancelled"
          @connection.calendar_events.where(remote_id: item["id"]).destroy_all
        else
          upsert(item)
        end
      end
    end

    def upsert(item)
      event = @connection.calendar_events.find_or_initialize_by(remote_id: item["id"])
      event.household = @connection.household
      event.source  ||= "manual"
      event.assign_attributes(Google::EventMapper.to_attributes(item))
      event.save!
    rescue ActiveRecord::RecordNotUnique
      # A concurrent pull inserted this remote_id first — apply our update to it.
      existing = @connection.calendar_events.find_by(remote_id: item["id"])
      existing&.update!(Google::EventMapper.to_attributes(item))
    end
  end
end

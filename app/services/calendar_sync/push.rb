# frozen_string_literal: true
# typed: false

module CalendarSync
  # Pushes a locally-authored CalendarEvent to the remote calendar (local ->
  # remote). On an update etag conflict (412) the remote version wins and the
  # admins get one notification. All writes that re-touch the local row are
  # wrapped in the echo guard so they don't bounce back through the push hooks.
  class Push
    def initialize(event)
      @event      = event
      @connection = event.calendar_connection
      @client     = Google::ApiClient.new(@connection)
    end

    def create
      Time.use_zone(tz) do
        result = @client.insert_event(@connection.calendar_id, Google::EventMapper.to_google(@event))
        stamp(result)
      end
    end

    def update
      return create if @event.remote_id.blank?

      Time.use_zone(tz) do
        result = @client.update_event(@connection.calendar_id, @event.remote_id,
                                      Google::EventMapper.to_google(@event), @event.etag)
        stamp(result)
      end
    rescue Google::Conflict
      remote_wins
    end

    private

    def tz
      @connection.household.timezone
    end

    def stamp(result)
      CalendarEvent.without_sync do
        @event.update_columns(remote_id: result["id"], etag: result["etag"])
      end
    end

    # Pull the authoritative remote version over the local edit, then notify.
    def remote_wins
      remote = @client.get_event(@connection.calendar_id, @event.remote_id)
      Time.use_zone(tz) do
        CalendarEvent.without_sync { @event.update!(Google::EventMapper.to_attributes(remote)) }
      end
      notify_conflict
    end

    def notify_conflict
      admins.each do |user|
        Notification.deliver(
          dedup_key: "calendar_conflict:#{@event.id}:#{@event.etag}:#{user.id}",
          household: @connection.household, user: user, notifiable: @event,
          kind:  "calendar_conflict",
          title: I18n.t("notification.calendar_conflict.title"),
          body:  I18n.t("notification.calendar_conflict.body", title: @event.title),
          url:   "/calendar"
        )
      end
    end

    def admins
      @connection.household.memberships.where(role: "admin").includes(:user).map(&:user)
    end
  end
end

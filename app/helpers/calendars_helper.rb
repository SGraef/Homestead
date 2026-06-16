# frozen_string_literal: true
# typed: false

module CalendarsHelper
  # Chunk a date range into weeks (arrays of 7 Dates) for the month grid.
  def calendar_weeks(range)
    range.to_a.each_slice(7)
  end

  # Localized day-of-month / weekday helpers driven off the household locale.
  def cal_day_cell_id(date)
    "cal-day-#{date.iso8601}"
  end

  # Format an event's time range for a chip (household timezone).
  def cal_event_time(event)
    tz = Household.current.timezone
    return t("calendar.all_day") if event.all_day

    start = event.starts_at.in_time_zone(tz).strftime("%H:%M")
    return start unless event.ends_at

    "#{start}–#{event.ends_at.in_time_zone(tz).strftime('%H:%M')}"
  end

  # The ?date= target for prev/next given the active view.
  def calendar_step(date, view, direction)
    case view
    when "day"    then date + direction
    when "agenda" then date + (direction * 30)
    else date >> direction # month
    end
  end
end

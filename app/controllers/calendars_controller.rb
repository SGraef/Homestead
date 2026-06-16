# frozen_string_literal: true
# typed: false

# Server-rendered calendar (month / agenda / day) showing events plus read-only
# todo due-dates. Navigated by ?date= (ISO) and ?view=, mirroring the meal-plan
# date navigation. All time bucketing happens in Household.current.timezone.
class CalendarsController < ApplicationController
  include HouseholdTimeZone
  before_action :ensure_household

  def show
    @view = %w[month agenda day].include?(params[:view]) ? params[:view] : "month"
    @date = parse_date(params[:date]) || Date.current
    @range = range_for(@view, @date)
    load_items(@range)
  end

  private

  def range_for(view, date)
    case view
    when "day"    then date..date
    when "agenda" then date..(date + 30)
    else
      (date.beginning_of_month.beginning_of_week(:monday))..(date.end_of_month.end_of_week(:monday))
    end
  end

  def load_items(range)
    from = range.first.in_time_zone.beginning_of_day
    to   = range.last.in_time_zone.end_of_day

    events = current_household.calendar_events.starting_between(from, to).order(:starts_at)
    @events_by_day = events.group_by { |e| e.starts_at.in_time_zone.to_date }

    @todos_by_day = current_household.todos.where(due_on: range).group_by(&:due_on)
  end

  def parse_date(str)
    str.present? ? Date.iso8601(str) : nil
  rescue ArgumentError
    nil
  end

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end
end

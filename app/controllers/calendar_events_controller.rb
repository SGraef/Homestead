# frozen_string_literal: true
# typed: false

class CalendarEventsController < ApplicationController
  include HouseholdTimeZone
  before_action :ensure_household
  before_action :set_event, only: %i[edit update destroy create_todo]

  def new
    @event = current_household.calendar_events.new(starts_at: default_start)
    authorize @event
  end

  def create
    @event = current_household.calendar_events.new(event_params.merge(source: "manual"))
    authorize @event
    if @event.save
      redirect_to calendar_path(date: local_date(@event).iso8601), notice: t("notices.event_created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @event
  end

  def update
    authorize @event
    if @event.update(event_params)
      redirect_to calendar_path(date: local_date(@event).iso8601), notice: t("notices.event_updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @event
    @event.destroy
    redirect_to calendar_path, notice: t("notices.event_deleted")
  end

  # POST /calendar/events/:id/create_todo — make a todo from a task-like manual
  # event (C7). One-hop: a generated event is never task_like?, so this never
  # loops; the new todo carries provenance and never spawns an event back.
  def create_todo
    authorize @event, :show?
    if @event.task_like? && !Todo.exists?(source_calendar_event_id: @event.id)
      todo = current_household.todos.create!(
        title: @event.title, creator: current_user,
        due_on: @event.starts_at.in_time_zone(current_household.timezone).to_date,
        source: "calendar_extraction", source_calendar_event: @event
      )
      redirect_to todo, notice: t("notices.todo_created")
    else
      redirect_to edit_calendar_event_path(@event)
    end
  end

  private

  def set_event
    @event = current_household.calendar_events.find(params[:id])
  end

  def event_params
    params.require(:calendar_event).permit(:title, :starts_at, :ends_at, :all_day)
  end

  def local_date(event)
    event.starts_at.in_time_zone(current_household.timezone).to_date
  end

  def default_start
    date = (Date.iso8601(params[:date]) rescue Date.current)
    date.in_time_zone.change(hour: 9) # in_time_zone uses the around_action zone
  end

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end
end

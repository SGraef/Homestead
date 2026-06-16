# frozen_string_literal: true
# typed: false

class TodoCommentsController < ApplicationController
  include HouseholdTimeZone
  before_action :ensure_household
  before_action :set_todo

  def create
    @comment = @todo.todo_comments.new(comment_params.merge(user: current_user, household: current_household))
    authorize @comment
    if @comment.save
      TodoNotifications.commented(@comment, actor: current_user)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @todo }
      end
    else
      redirect_to @todo, alert: @comment.errors.full_messages.to_sentence
    end
  end

  def destroy
    @comment = @todo.todo_comments.find(params[:id])
    authorize @comment
    @comment.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @todo }
    end
  end

  # POST /todos/:todo_id/comments/:id/confirm_event — turn the detected German
  # date in this comment into a calendar event (suggest-then-confirm, C5).
  def confirm_event
    comment   = @todo.todo_comments.find(params[:id])
    authorize comment, :create?
    suggestion = GermanDateExtractor.call(comment.body)

    if suggestion && !CalendarEvent.exists?(source_record: comment)
      current_household.calendar_events.create!(
        title:        suggestion.title,
        starts_at:    suggestion.to_time_in_zone,
        all_day:      suggestion.all_day?,
        source:       "comment_extraction",
        source_record: comment
      )
      redirect_to @todo, notice: t("notices.event_created")
    else
      redirect_to @todo
    end
  end

  # POST /todos/:todo_id/comments/:id/dismiss_suggestion — never re-offer it.
  def dismiss_suggestion
    comment    = @todo.todo_comments.find(params[:id])
    authorize comment, :create?
    suggestion = GermanDateExtractor.call(comment.body)
    comment.suggestion_dismissals.find_or_create_by!(span_hash: suggestion.span_hash) if suggestion
    redirect_to @todo
  end

  private

  def set_todo
    @todo = current_household.todos.find(params[:todo_id])
  end

  def comment_params
    params.require(:todo_comment).permit(:body)
  end

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end
end

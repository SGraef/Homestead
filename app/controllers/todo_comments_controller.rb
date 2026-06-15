# frozen_string_literal: true
# typed: false

class TodoCommentsController < ApplicationController
  before_action :ensure_household
  before_action :set_todo

  def create
    @comment = @todo.todo_comments.new(comment_params.merge(user: current_user, household: current_household))
    authorize @comment
    if @comment.save
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

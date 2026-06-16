# frozen_string_literal: true
# typed: false

class TodosController < ApplicationController
  before_action :ensure_household
  before_action :set_todo, only: %i[show edit update destroy transition follow unfollow]

  def index
    @todos = policy_scope(current_household.todos)
             .includes(:assignee, :creator)
             .order(Arel.sql("FIELD(status, 'open', 'in_progress', 'done'), created_at DESC"))
  end

  def show
    authorize @todo
    @comment = @todo.todo_comments.new
  end

  def new
    @todo = current_household.todos.new
    authorize @todo
  end

  def create
    @todo = current_household.todos.new(todo_params.merge(creator: current_user))
    authorize @todo
    if @todo.save
      redirect_to @todo, notice: t("notices.todo_created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @todo
  end

  def update
    authorize @todo
    if @todo.update(todo_params)
      TodoNotifications.assigned(@todo, actor: current_user) if @todo.saved_change_to_assignee_id?
      redirect_to @todo, notice: t("notices.todo_updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @todo
    @todo.destroy
    redirect_to todos_path, notice: t("notices.todo_deleted")
  end

  # POST /todos/:id/transition?to=in_progress — one-tap state change.
  def transition
    authorize @todo, :transition?
    if @todo.transition_to(params[:to])
      TodoNotifications.todo_changed(
        @todo, actor: current_user,
        summary: t("notification.status_changed", state: t("todo.states.#{@todo.status}"))
      )
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to todos_path, notice: t("notices.todo_updated") }
      end
    else
      redirect_to todos_path, alert: t("notices.todo_invalid_transition")
    end
  end

  # POST /todos/:id/follow
  def follow
    authorize @todo, :show?
    @todo.follow!(current_user)
    redirect_to @todo, notice: t("notices.todo_followed")
  end

  # DELETE /todos/:id/unfollow
  def unfollow
    authorize @todo, :show?
    @todo.unfollow!(current_user)
    redirect_to @todo, notice: t("notices.todo_unfollowed")
  end

  private

  def set_todo
    @todo = current_household.todos.find(params[:id])
  end

  def todo_params
    params.require(:todo).permit(:title, :description, :status, :assignee_id, :due_on)
  end

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end
end

# frozen_string_literal: true
# typed: false

require "rails_helper"

# Regression coverage for the todo show page. Previously #show built the
# new-comment form object via `@todo.todo_comments.new`, which appended an
# unsaved (nil created_at) record to the rendered comments collection and made
# the page 500 on `l(nil)` -- for every todo, including the ones generated from
# document imports.
RSpec.describe "Todos show" do
  let(:user)       { create(:user) }
  let!(:household) { create(:household, admin: user) }

  before { login_via_post(user) }

  it "renders a todo with no comments" do
    todo = create(:todo, household: household)
    get todo_path(todo)
    expect(response).to have_http_status(:ok)
  end

  it "renders a todo that has comments" do
    todo = create(:todo, household: household)
    create(:todo_comment, todo: todo, household: household, user: user)
    get todo_path(todo)
    expect(response).to have_http_status(:ok)
  end

  it "renders a document-sourced reminder todo" do
    document = create(:document, household: household, user: user)
    todo = create(:todo, household: household, source: "document",
                         source_document: document, due_on: Date.current + 7)
    get todo_path(todo)
    expect(response).to have_http_status(:ok)
  end
end

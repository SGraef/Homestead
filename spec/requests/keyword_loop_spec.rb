# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Keyword calendar/todo loop (C5/C7)" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin, timezone: "Europe/Berlin") }

  before { login_via_post(admin) }

  def comment_on(todo, body)
    todo.todo_comments.create!(household: household, user: admin, body: body)
  end

  describe "C5: comment date -> calendar event (suggest-then-confirm)" do
    it "creates a provenance-tagged event from a detected German date" do
      todo    = create(:todo, household: household)
      comment = comment_on(todo, "Termin am 20. Juni um 14 Uhr")

      expect { post confirm_event_todo_comment_path(todo, comment) }
        .to change(CalendarEvent, :count).by(1)

      event = CalendarEvent.last
      expect(event.source).to eq("comment_extraction")
      expect(event.source_record).to eq(comment)
      expect(event.starts_at.in_time_zone("Europe/Berlin").hour).to eq(14)
    end

    it "never creates a second event for the same comment" do
      todo    = create(:todo, household: household)
      comment = comment_on(todo, "Treffen am 20. Juni")
      post confirm_event_todo_comment_path(todo, comment)

      expect { post confirm_event_todo_comment_path(todo, comment) }
        .not_to change(CalendarEvent, :count)
    end

    it "records a dismissal so the chip stops nagging" do
      todo    = create(:todo, household: household)
      comment = comment_on(todo, "Termin am 20. Juni")

      expect { post dismiss_suggestion_todo_comment_path(todo, comment) }
        .to change(SuggestionDismissal, :count).by(1)
    end
  end

  describe "C7: task-like event -> todo (one-hop, provenance-gated)" do
    it "creates a provenance-tagged todo from a manual task-like event" do
      event = create(:calendar_event, household: household, title: "Geschenk kaufen",
                     source: "manual", starts_at: Time.utc(2026, 6, 20, 8))

      expect { post create_todo_calendar_event_path(event) }.to change(Todo, :count).by(1)

      todo = Todo.last
      expect(todo.source).to eq("calendar_extraction")
      expect(todo.source_calendar_event).to eq(event)
      expect(todo.due_on).to eq(Date.new(2026, 6, 20))
    end

    it "offers no todo for a non-task event (keyword gate)" do
      event = create(:calendar_event, household: household, title: "Kino", source: "manual")
      expect { post create_todo_calendar_event_path(event) }.not_to change(Todo, :count)
    end

    it "never re-scans a generated event (loop guard)" do
      event = create(:calendar_event, household: household, title: "kaufen", source: "comment_extraction")
      expect(event.task_like?).to be(false)
      expect { post create_todo_calendar_event_path(event) }.not_to change(Todo, :count)
    end

    it "does not duplicate a todo from the same event" do
      event = create(:calendar_event, household: household, title: "Geschenk kaufen", source: "manual")
      post create_todo_calendar_event_path(event)
      expect { post create_todo_calendar_event_path(event) }.not_to change(Todo, :count)
    end
  end
end

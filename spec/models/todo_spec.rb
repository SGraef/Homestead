# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Todo do
  let(:household) { create(:household) }

  it "validates title presence and status inclusion" do
    expect(build(:todo, title: nil)).not_to be_valid
    expect(build(:todo, status: "bogus")).not_to be_valid
    expect(build(:todo)).to be_valid
  end

  describe "#transition_to (full state matrix)" do
    legal   = { "open" => %w[in_progress], "in_progress" => %w[open done], "done" => %w[in_progress] }
    illegal = { "open" => %w[done], "in_progress" => %w[], "done" => %w[open] }

    Todo::STATES.each do |from|
      Todo::STATES.each do |to|
        it "#{from} -> #{to}" do
          todo = create(:todo, household: household, status: from)
          allowed = legal.fetch(from).include?(to)

          result = todo.transition_to(to)

          expect(result).to eq(allowed)
          expect(todo.reload.status).to eq(allowed ? to : from)
        end
      end
    end

    it "treats a no-op self-transition as illegal (no save, no side effects)" do
      todo = create(:todo, household: household, status: "in_progress")
      expect(todo.transition_to("in_progress")).to be(false)
    end

    it "rejects the documented illegal jumps" do
      illegal.each do |from, tos|
        tos.each do |to|
          todo = create(:todo, household: household, status: from)
          expect(todo.transition_to(to)).to be(false), "expected #{from}->#{to} to be rejected"
        end
      end
    end
  end

  describe "completed_at" do
    it "is set on entering done and cleared on leaving it" do
      todo = create(:todo, household: household, status: "in_progress")
      todo.transition_to("done")
      expect(todo.completed_at).to be_present

      todo.transition_to("in_progress")
      expect(todo.reload.completed_at).to be_nil
    end
  end

  describe "#next_state" do
    it "advances open -> in_progress -> done -> nil" do
      expect(build(:todo, status: "open").next_state).to eq("in_progress")
      expect(build(:todo, status: "in_progress").next_state).to eq("done")
      expect(build(:todo, status: "done").next_state).to be_nil
    end
  end
end

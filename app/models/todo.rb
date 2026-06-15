# frozen_string_literal: true
# typed: false

# A collaborative todo owned by the single household. Every member can see and
# work on it. The lifecycle is a small, fixed state machine (no workflow gem,
# no admin-editable states), mirroring the GroceryItem::STATUSES /
# Membership::ROLES string-constant precedent.
class Todo < ApplicationRecord
  STATES = %w[open in_progress done].freeze

  # Allowed state transitions. A target not listed for the current state (and a
  # no-op self-transition) is rejected by {#transition_to} — callers rely on
  # this to avoid firing spurious "changed" notifications in later phases.
  TRANSITIONS = {
    "open"        => %w[in_progress],
    "in_progress" => %w[open done],
    "done"        => %w[in_progress]
  }.freeze

  belongs_to :household
  belongs_to :creator,  class_name: "User", optional: true
  belongs_to :assignee, class_name: "User", optional: true

  has_many :todo_comments, -> { order(:created_at) }, dependent: :destroy

  validates :title, presence: true, length: { maximum: 200 }
  validates :status, inclusion: { in: STATES }

  scope :open_state,   -> { where(status: "open") }
  scope :in_progress,  -> { where(status: "in_progress") }
  scope :done,         -> { where(status: "done") }
  scope :active,       -> { where.not(status: "done") }

  # @param to [String]
  # @return [Boolean] whether `status` may legally move to `to`.
  def can_transition_to?(to)
    TRANSITIONS.fetch(status, []).include?(to)
  end

  # Move to a new state. Returns false (no save) for an illegal or no-op
  # transition; sets/clears completed_at on entering/leaving "done".
  #
  # @param to [String]
  # @return [Boolean] true if the transition was applied and saved
  def transition_to(to)
    return false unless can_transition_to?(to)

    self.status       = to
    self.completed_at = (to == "done" ? Time.current : nil)
    save
  end

  # @return [String, nil] the next state for the one-tap "advance" pill.
  def next_state
    TRANSITIONS.fetch(status, []).find { |s| STATES.index(s).to_i > STATES.index(status).to_i }
  end
end

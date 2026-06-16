# frozen_string_literal: true
# typed: false

# An in-app notification for one recipient. The persisted row is the reliable
# baseline (shown in the nav bell); push delivery is layered on later. Reading
# via the bell or (later) via a push tap marks the same row.
class Notification < ApplicationRecord
  KINDS = %w[assigned todo_changed comment_added].freeze

  belongs_to :household
  belongs_to :user # recipient
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :title, presence: true
  validates :dedup_key, presence: true, uniqueness: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Idempotent create keyed on dedup_key: the same domain event (re)processed
  # never yields a second row. A duplicate surfaces as RecordInvalid (model
  # uniqueness validation) or RecordNotUnique (DB index, on a race) — both
  # resolve to the existing row; any other validation error re-raises.
  #
  # @return [Notification]
  def self.deliver(dedup_key:, **attrs)
    create!(attrs.merge(dedup_key: dedup_key))
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    find_by(dedup_key: dedup_key) || raise(e)
  end

  def read? = read_at.present?

  def mark_read!
    update!(read_at: Time.current) unless read?
  end
end

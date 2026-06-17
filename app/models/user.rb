# frozen_string_literal: true
# typed: false

# A user authenticates with email + password (Sorcery) and is a member of the
# single household this instance serves (via {Membership}). Because Homestead is
# single-household-per-instance, every member has full access to the household's
# data; the membership role (admin/member) only governs settings, member
# management and destructive deletes.
#
# @!attribute [rw] email
#   @return [String] unique email used as login
# @!attribute [rw] name
#   @return [String, nil] optional display name
class User < ApplicationRecord
  authenticates_with_sorcery!

  has_many :memberships, dependent: :destroy
  has_many :households, through: :memberships
  has_many :api_tokens, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :todo_follows, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy

  validates :email,
            presence:   true,
            uniqueness: { case_sensitive: false },
            format:     { with: URI::MailTo::EMAIL_REGEXP }
  validates :password,
            length:       { minimum: 8 },
            confirmation: true,
            if:           -> { new_record? || changes[:crypted_password] }
  validates :password_confirmation, presence: true, if: -> { new_record? }

  before_save { self.email = email&.downcase&.strip }

  # @return [Household, nil] the sole household this instance serves. Kept for
  #   backward compatibility; delegates to {Household.current} so it can never
  #   disagree with the instance-wide canonical household.
  def default_household
    Household.current
  end

  # @param household [Household]
  # @return [Boolean]
  def admin_of?(household)
    memberships.exists?(household_id: household.id, role: "admin")
  end
end

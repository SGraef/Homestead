# frozen_string_literal: true
# typed: true

# A user authenticates with email + password (Sorcery) and may belong to one or
# many households via {Membership}. All Pundit checks scope through the user's
# household memberships.
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

  validates :email,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password,
            length: { minimum: 8 },
            confirmation: true,
            if: -> { new_record? || changes[:crypted_password] }
  validates :password_confirmation, presence: true, if: -> { new_record? }

  before_save { self.email = email&.downcase&.strip }

  # @return [Household, nil] the first household the user belongs to
  def default_household
    households.first
  end

  # @param household [Household]
  # @return [Boolean]
  def admin_of?(household)
    memberships.exists?(household_id: household.id, role: "admin")
  end
end

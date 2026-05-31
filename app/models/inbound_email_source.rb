# frozen_string_literal: true
# typed: false

# A configured IMAP mailbox that the recurring inbound-receipts job
# drains. Each row is owned by the user who set it up; other household
# members can see that a source exists (and its label / host /
# username) but only the owner can see/change the password.
#
# The password is encrypted at rest via Active Record's `encrypts`,
# wired to the per-deployment SECRET_KEY_BASE in
# config/initializers/active_record_encryption.rb.
class InboundEmailSource < ApplicationRecord
  encrypts :imap_password

  belongs_to :household
  belongs_to :user

  validates :label,         presence: true, length: { maximum: 80 }
  validates :imap_host,     presence: true, length: { maximum: 255 }
  validates :imap_port,     presence:     true,
                            numericality: { only_integer: true,
                                            greater_than: 0, less_than: 65_536 }
  validates :imap_username, presence: true, length: { maximum: 255 }
  validates :imap_password, presence: true
  validates :folder,        presence: true, length: { maximum: 255 }

  validates :imap_username,
            uniqueness: { scope:          %i[household_id imap_host folder],
                          case_sensitive: false,
                          message:        :duplicate_source }

  scope :ordered, -> { order(:label, :id) }

  # @param user [User] viewing user
  # @return [Boolean] true if `user` can edit / delete / see the
  #   password for this row.
  def manageable_by?(user)
    user_id == user&.id
  end

  # Sets the encrypted password only if a non-blank value is given.
  # Used by the edit form so submitting without retyping the password
  # leaves the existing one intact.
  def assign_password_if_present(value)
    self.imap_password = value if value.to_s.strip.present?
  end
end

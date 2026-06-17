# frozen_string_literal: true
# typed: ignore

# Homestead moved from multi-household to single-household-per-instance. The
# canonical household is the oldest one (lowest id); everything else is resolved
# via Household.current. This migration is NON-DESTRUCTIVE: it never drops a
# table, column or row, and never deletes other households. It only ensures that
# after the collapse:
#
#   1. every existing user is a member of the canonical household (so nobody is
#      locked out of the now-shared data), and
#   2. the canonical household has at least one admin (so it stays manageable).
#
# Idempotent: safe to re-run. Uses find_or_create_by against the
# [user_id, household_id] unique index so already-members are untouched.
class BackfillSingleHouseholdMemberships < ActiveRecord::Migration[8.0]
  # Lightweight, schema-pinned models so this migration is independent of any
  # future changes to the real app models.
  class MigrationHousehold < ActiveRecord::Base
    self.table_name = "households"
  end

  class MigrationMembership < ActiveRecord::Base
    self.table_name = "memberships"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    canonical = MigrationHousehold.order(:id).first
    return say("No household present; nothing to backfill.") unless canonical

    others = MigrationHousehold.where.not(id: canonical.id).count
    if others.positive?
      say "Found #{others} additional household(s). Keeping ##{canonical.id} " \
          "(#{canonical.name.inspect}) as the canonical household. The others' " \
          "rows are left untouched -- run `rake homestead:single_household:merge` " \
          "to fold their data in, or ignore them."
    end

    # Users who held an admin role in ANY household become admins of the
    # canonical one; everyone else is a plain member.
    admin_user_ids = MigrationMembership.where(role: "admin").distinct.pluck(:user_id).to_set

    MigrationUser.find_each do |user|
      membership = MigrationMembership.find_or_initialize_by(
        user_id:      user.id,
        household_id: canonical.id
      )
      desired_role = admin_user_ids.include?(user.id) ? "admin" : (membership.role.presence || "member")
      # Never downgrade an existing canonical admin to member.
      desired_role = "admin" if membership.role == "admin"
      membership.role = desired_role
      membership.save!
    end

    ensure_at_least_one_admin(canonical)
  end

  # Down is a no-op: the backfilled memberships are valid in both the multi- and
  # single-household worlds, and removing them could lock users out. Nothing to
  # reverse.
  def down
    say "BackfillSingleHouseholdMemberships is not reversible (no-op down)."
  end

  private

  def ensure_at_least_one_admin(canonical)
    members = MigrationMembership.where(household_id: canonical.id)
    return if members.exists?(role: "admin")

    oldest = members.order(:id).first
    return unless oldest

    oldest.update!(role: "admin")
    say "No admin on household ##{canonical.id}; promoted membership ##{oldest.id} to admin."
  end
end

# frozen_string_literal: true

namespace :pantria do
  namespace :single_household do
    desc "Fold every non-canonical household's data into Household.current " \
         "(the oldest household). OPTIONAL and opt-in. May produce duplicate " \
         "products/stores that share a name across households -- review afterwards. " \
         "Run a database backup first."
    task merge: :environment do
      canonical = Household.current
      abort("No household present; nothing to merge.") unless canonical

      others = Household.where.not(id: canonical.id).to_a
      if others.empty?
        puts "Only one household (##{canonical.id}). Nothing to merge."
        next
      end

      # Every table that carries a household_id, reassigned to the canonical
      # household. Derived from the schema so it stays correct as tables change.
      tables = ActiveRecord::Base.connection.tables.select do |t|
        ActiveRecord::Base.connection.column_exists?(t, :household_id)
      end
      # memberships is special-cased below (unique on [user_id, household_id]).
      tables -= ["memberships"]

      other_ids = others.map(&:id)
      puts "Merging #{others.size} household(s) #{other_ids.inspect} into " \
           "##{canonical.id} (#{canonical.name.inspect})."

      ActiveRecord::Base.transaction do
        tables.each do |table|
          updated = ActiveRecord::Base.connection.update(
            ActiveRecord::Base.sanitize_sql_array([
              "UPDATE #{table} SET household_id = ? WHERE household_id IN (?)",
              canonical.id, other_ids
            ])
          )
          puts "  #{table}: reassigned #{updated} row(s)."
        end

        # Memberships: move members onto the canonical household without
        # violating the [user_id, household_id] unique index. Add a membership
        # only for users who aren't members of the canonical household yet.
        Membership.where(household_id: other_ids).find_each do |m|
          Membership.find_or_create_by!(user_id: m.user_id, household_id: canonical.id) do |nm|
            nm.role = m.role
          end
        end
        Membership.where(household_id: other_ids).delete_all

        # The now-empty households can be removed safely.
        Household.where(id: other_ids).destroy_all
      end

      puts "Done. The instance now has exactly one household (##{canonical.id})."
    end
  end
end

# frozen_string_literal: true
# typed: ignore

return unless Rails.env.development?

user = User.find_or_create_by!(email: "demo@homestead.local") do |u|
  u.name = "Demo Benutzer"
  u.password = u.password_confirmation = "password123"
end
# Sorcery's `before_create :setup_activation` forces `activation_state` back
# to "pending" regardless of what we set in the block above, so flip it after
# save. update_columns skips callbacks (no activation-success email needed).
user.update_columns(activation_state: "active", activation_token: nil) unless user.activation_state == "active"

# Single-household-per-instance: reuse the existing household if there is one,
# otherwise create the demo household. Never creates a second household.
household = Household.current || Household.create!(name: "Demo-Haushalt", timezone: "Europe/Berlin")
Membership.find_or_create_by!(user: user, household: household) { |m| m.role = "admin" }

store = household.stores.find_or_create_by!(name: "Supermarkt um die Ecke") do |s|
  s.chain = "REWE"
end

milk = household.products.find_or_create_by!(barcode: "4006381333924") do |p|
  p.name = "Vollmilch 1L"
  p.unit = "l"
  p.category = "Milchprodukte"
end

Price.find_or_create_by!(product: milk, store: store, observed_on: Date.current) do |p|
  p.amount_cents = 119
  p.currency = "EUR"
end

fridge = household.locations.find_by!(kind: "fridge")
household.storage_items.find_or_create_by!(product: milk, location: fridge) do |i|
  i.quantity = 2
  i.expires_on = 7.days.from_now.to_date
end

puts "Seeded demo household with one product, one store, one price, one storage item."

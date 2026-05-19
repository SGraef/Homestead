# frozen_string_literal: true
# typed: ignore

# No acronyms registered. Earlier `API` / `EAN` / `UPC` rules forced
# Zeitwerk to expect e.g. API::V1::BaseController for app/controllers/api/v1/*,
# but every controller in that tree is declared as `module Api`. Eager loading
# in CI tripped on the mismatch -- the codebase consistently uses Api / Ean /
# Upc camelization, so we leave the inflector at its default.
ActiveSupport::Inflector.inflections(:en) do |_inflect|
end

# frozen_string_literal: true
# typed: true

# Base class for all ActiveRecord models. Use this rather than ActiveRecord::Base
# directly so cross-cutting concerns (Sorbet sigs, enums, etc.) live in one place.
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

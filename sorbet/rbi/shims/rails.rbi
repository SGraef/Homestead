# typed: true

# Tiny shim: only needed until `bin/tapioca gems` runs in the dev container.
class ActiveRecord::Base; end
class ActionController::Base; end
class ActionController::API; end

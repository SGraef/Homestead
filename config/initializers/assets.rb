# frozen_string_literal: true

# Vendored JavaScript modules (e.g. @zxing/browser) live in
# vendor/javascript and get pinned by name in config/importmap.rb.
# Propshaft / Sprockets need the path on the asset load list so the
# files actually get fingerprinted and served from /assets/.
Rails.application.config.assets.paths << Rails.root.join("vendor/javascript")

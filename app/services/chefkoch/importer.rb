# frozen_string_literal: true
# typed: false

require "net/http"
require "json"
require "uri"

module Chefkoch
  # Import a Chefkoch recipe by URL.
  #
  # Chefkoch's pages are a Nuxt SPA -- there's no JSON-LD on the static
  # HTML and the rendered recipe arrives client-side via their public
  # JSON API at:
  #
  #   GET https://api.chefkoch.de/v2/recipes/<recipe-id>
  #
  # We pull the recipe ID straight out of the URL path
  # (`/rezepte/<digits>/<slug>.html`), hit that endpoint, then build a
  # local Recipe + RecipeIngredient rows. Ingredients are mapped to the
  # household's Product catalog by case-insensitive name; if no match
  # exists a new Product is created on the fly so the row can link
  # back to a real catalog entry (and storage on-hand calculations
  # keep working).
  class Importer
    API_URL_FMT = "https://api.chefkoch.de/v2/recipes/%<id>s"
    USER_AGENT  = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                  "(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
    OPEN_TIMEOUT = 6
    READ_TIMEOUT = 15

    # Chefkoch units we can map cleanly onto Product::UNITS. Anything
    # not in this set is kept on the RecipeIngredient as the row-level
    # `unit` override; the Product itself defaults to "pcs".
    PRODUCT_UNIT_MAP = {
      "g"  => "g",
      "kg" => "kg",
      "ml" => "ml",
      "l"  => "l"
    }.freeze

    PIECE_UNITS = ["Stück", "Stk.", "Stk", "St.", "St"].freeze

    Result = Struct.new(:recipe, :ingredients_created, :products_created,
                        keyword_init: true)

    class ImportError < StandardError; end

    # @param url [String] full Chefkoch recipe URL
    # @param household [Household]
    # @return [Result]
    def self.call(url:, household:)
      new(url: url, household: household).call
    end

    def initialize(url:, household:)
      @url       = url.to_s
      @household = household
    end

    def call
      recipe_id = extract_recipe_id(@url)
      raise ImportError, I18n.t("recipe.import.bad_url") unless recipe_id

      payload = fetch_recipe(recipe_id)
      build_recipe(payload)
    end

    private

    # Matches /rezepte/<digits>/<slug>.html and a few variants.
    def extract_recipe_id(url)
      m = url.match(%r{/rezepte/(\d{6,})/})
      m && m[1]
    end

    def fetch_recipe(id)
      uri  = URI.parse(format(API_URL_FMT, id: id))
      SafeHttp.validate_uri!(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      req = Net::HTTP::Get.new(
        uri.request_uri,
        "User-Agent" => USER_AGENT,
        "Accept"     => "application/json"
      )
      resp = http.request(req)

      case resp
      when Net::HTTPNotFound
        raise ImportError, I18n.t("recipe.import.not_found")
      when Net::HTTPSuccess
        JSON.parse(resp.body)
      else
        raise ImportError, I18n.t("recipe.import.upstream_error", code: resp.code)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError,
           Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      raise ImportError, "#{e.class}: #{e.message}"
    rescue JSON::ParserError
      raise ImportError, I18n.t("recipe.import.bad_payload")
    end

    def build_recipe(data)
      title = data["title"].to_s.strip
      raise ImportError, I18n.t("recipe.import.no_title") if title.empty?

      ingredients_attrs, products_created = build_ingredient_attrs(data["ingredientGroups"])

      recipe = @household.recipes.build(
        name:                          title,
        description:                   data["subtitle"].presence,
        servings:                      Integer(data["servings"] || 1),
        prep_minutes:                  data["preparationTime"],
        cook_minutes:                  data["cookingTime"],
        notes:                         compose_notes(data),
        recipe_ingredients_attributes: ingredients_attrs
      )
      # Pull Chefkoch's flat tag list ("vegetarisch", "schnell",
      # "italienisch", …). `fullTags` is richer but full of hierarchy
      # crud the suggester doesn't need.
      recipe.tag_list = Array(data["tags"]).map(&:to_s)
      recipe.save!

      Result.new(
        recipe:              recipe,
        ingredients_created: recipe.recipe_ingredients.size,
        products_created:    products_created
      )
    end

    # Build nested-attribute hashes for accepts_nested_attributes_for,
    # creating any missing Product rows side-effect-style. Returns the
    # hash array + the count of new products.
    def build_ingredient_attrs(groups)
      attrs    = []
      created  = 0
      position = 0

      Array(groups).each do |group|
        Array(group["ingredients"]).each do |ing|
          ing_name = ing["name"].to_s.strip
          next if ing_name.empty?

          product, was_new = resolve_product(ing_name, ing["unit"])
          created += 1 if was_new

          # Chefkoch returns `amount: 0` for to-taste rows ("Salz nach
          # Geschmack", "1 Prise Pfeffer"). RecipeIngredient validates
          # quantity > 0, so fall back to 1 -- the recipe row still
          # reads sensibly ("1 Prise Salz") and `usageInfo` carries any
          # qualifier through.
          qty = ing["amount"].to_d
          qty = BigDecimal(1) if qty <= 0

          attrs << {
            product_id: product.id,
            quantity:   qty,
            unit:       row_unit_for(ing["unit"]),
            notes:      ing["usageInfo"].presence,
            position:   position
          }
          position += 1
        end
      end
      [attrs, created]
    end

    # Case-insensitive product lookup; creates a new Product if absent.
    # @return [[Product, Boolean]] (product, was_new)
    def resolve_product(name, chefkoch_unit)
      existing = @household.products.where("LOWER(name) = ?", name.downcase).first
      return [existing, false] if existing

      product = @household.products.create!(
        name: name,
        unit: product_unit_for(chefkoch_unit)
      )
      [product, true]
    end

    # Map Chefkoch's unit string to a Product::UNITS value. Unknown
    # units fall through to "pcs".
    def product_unit_for(chefkoch_unit)
      cu = chefkoch_unit.to_s.strip
      return PRODUCT_UNIT_MAP[cu] if PRODUCT_UNIT_MAP.key?(cu)
      return "pcs" if PIECE_UNITS.include?(cu)

      "pcs"
    end

    # The override unit we store on the RecipeIngredient row: keep
    # Chefkoch's literal string when it doesn't map cleanly (so a
    # recipe still reads "4 EL Öl" instead of being squashed to
    # "4 pcs"). When the unit DOES map to the product's canonical
    # unit, leave it blank so the product unit drives display.
    def row_unit_for(chefkoch_unit)
      cu = chefkoch_unit.to_s.strip
      return nil if cu.empty?
      return nil if PRODUCT_UNIT_MAP.key?(cu)

      cu
    end

    # Cook instructions + any free-form text on the API payload get
    # concatenated into the Recipe's `notes` so the show page renders
    # them.
    def compose_notes(data)
      sections = [data["instructions"], data["miscellaneousText"]].map { |s| s.to_s.strip }.reject(&:empty?)
      sections.empty? ? nil : sections.join("\n\n")
    end
  end
end

# frozen_string_literal: true
# typed: false

# Single source of truth for the primary navigation IA. The sidebar (desktop),
# the "More" sheet (mobile) and the bottom tab bar all read from here so the
# structure never drifts between surfaces.
module NavigationHelper
  # Grouped destinations. Each item: label (i18n), path, icon (IconHelper key).
  # @return [Array<Hash>]
  def primary_nav
    [
      { key: "kitchen", items: [
        { label: t("nav.storage"),      path: storage_items_path,  icon: :box },
        { label: t("nav.freezer"),      path: freezer_path,        icon: :snowflake },
        { label: t("nav.grocery_list"), path: grocery_items_path,  icon: :cart },
        { label: t("nav.scan"),         path: scan_products_path,  icon: :scan },
        { label: t("nav.products"),     path: products_path,       icon: :package }
      ] },
      { key: "shopping", items: [
        { label: t("nav.offers"),   path: offers_path,   icon: :tag },
        { label: t("nav.receipts"), path: receipts_path, icon: :receipt },
        { label: t("nav.expenses"), path: expenses_path, icon: :wallet },
        { label: t("nav.stores"),   path: stores_path,   icon: :store }
      ] },
      { key: "cooking", items: [
        { label: t("nav.recipes"),   path: recipes_path,   icon: :book },
        { label: t("nav.meal_plan"), path: meal_plan_path, icon: :utensils }
      ] },
      { key: "home", items: [
        { label: t("nav.todos"),    path: todos_path,    icon: :check },
        { label: t("nav.calendar"), path: calendar_path, icon: :calendar }
      ] }
    ]
  end

  # System destinations that live in the sidebar footer / sheet footer rather
  # than a labelled group.
  # @return [Array<Hash>]
  def system_nav
    [
      { label: t("nav.household"), path: household_path, icon: :settings },
      { label: t("nav.jobs"),      path: "/jobs",        icon: :activity }
    ]
  end

  # The four most-used destinations surfaced as bottom-bar tabs on mobile.
  # @return [Array<Hash>]
  def bottom_nav_tabs
    [
      { label: t("nav.storage"),      path: storage_items_path, icon: :box },
      { label: t("nav.grocery_list"), path: grocery_items_path, icon: :cart },
      { label: t("nav.todos"),        path: todos_path,         icon: :check },
      { label: t("nav.calendar"),     path: calendar_path,      icon: :calendar }
    ]
  end

  # Highlight a nav entry for its own page and any nested page beneath it
  # (e.g. /storage_items/5 keeps "Storage" active).
  # @return [Boolean]
  def nav_link_active?(path)
    here = request.path
    here == path || here.start_with?("#{path}/")
  end
end

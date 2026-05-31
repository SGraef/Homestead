# frozen_string_literal: true
# typed: ignore

Rails.application.routes.draw do
  # --- Auth (Sorcery) -------------------------------------------------------
  get  "/login",  to: "sessions#new", as: :login
  post "/login",  to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  resource :registration, only: %i[new create]

  # Activation flow (link arriving in the activation email).
  get  "/activate/:token", to: "activations#show",   as: :activation
  post "/activations",     to: "activations#create", as: :resend_activation

  # Password reset flow.
  resources :password_resets, only: %i[new create edit update], param: :token

  # --- Web (Hotwire / ERB) --------------------------------------------------
  root to: "dashboard#index"

  # Declared above `resources :households` so the literal path
  # /households/inbound_emails wins against the dynamic
  # /households/:id pattern that would otherwise try to look up a
  # Household with id="inbound_emails" and 404.
  resources :inbound_email_sources,
            only: %i[index new create edit update destroy],
            path: "households/inbound_emails"

  resources :households, only: %i[index show new create edit update destroy] do
    member do
      post :switch       # set session[:household_id] and use this household
      delete :leave      # current_user removes their own membership
    end
    resources :memberships, only: %i[create update destroy]
  end

  resources :stores
  resources :products do
    resources :prices,           only: %i[index new create edit update destroy]
    resources :product_barcodes, only: %i[create update destroy]

    collection do
      get  :scan            # Frontend barcode scanner UI
      get  :lookup          # AJAX lookup by barcode (turbo-stream / json)
      get  :search          # JSON search by name + brand (form fetch button)
      post :attach_barcode  # Add a scanned barcode as alternate to a chosen product
    end
  end

  resources :storage_items do
    member do
      post :decrement
      post :move
    end
  end

  resources :locations, only: %i[index new create edit update destroy]
  resources :grocery_items do
    member do
      patch :purchase # mark as bought (typically called after a barcode scan)
    end

    collection do
      post   :scan_purchase    # bulk: barcode-scan a just-bought item
      delete :purge_purchased  # bulk: remove every purchased row
    end
  end

  resources :receipts, only: %i[index new create show destroy] do
    member do
      post :confirm
      post :reprocess
    end
  end

  resources :expenses, only: :index

  resources :offers, only: :index do
    collection do
      post :sync
      post :reset
    end
    post :add_to_list, on: :member
  end
  resources :offer_blocklist_entries, only: %i[create destroy], path: "offers/blocklist"
  resources :offer_retailer_filters,  only: %i[create destroy], path: "offers/retailers" do
    # Bulk-replace endpoint for the multi-select checkbox form on
    # /offers. Submitting the form sends the full intended allow-list;
    # the controller diffs against the current rows in one request.
    collection { put :bulk }
  end
  resources :offer_watchlist_entries, only: %i[create destroy], path: "offers/watchlist"
  resources :offer_categories, only: %i[index create update destroy], path: "offers/categories" do
    post :reset_defaults, on: :collection
    resources :offer_category_keywords, only: %i[create destroy], path: "keywords"
  end
  resources :manual_offers, only: %i[new create edit update destroy], path: "offers/manual"

  resources :recipes do
    # Add-an-ingredient form on the show page goes to a flat nested route.
    resources :ingredients, only: %i[create destroy], controller: "recipe_ingredients" do
      # POST /recipes/:recipe_id/ingredients/:id/consume — "Used" button:
      # decrement household storage by this ingredient's quantity.
      post :consume, on: :member
    end
    member do
      # POST /recipes/:id/shop_missing -- add every short-on-stock
      # ingredient (by deficit) to the grocery list.
      post :shop_missing
    end
    collection { post :import } # POST /recipes/import -- Chefkoch URL importer
  end

  # Weekly meal-plan grid. Singular resource (one per household,
  # navigated by ?date=).
  resource :meal_plan, only: %i[show] do
    # POST /meal_plan/suggest — auto-fill the week's dinner slots
    # using MealPlanSuggester.
    post :suggest
  end
  resources :meal_plan_entries, only: %i[create destroy]

  # Solid Queue dashboard. The mounted engine doesn't run through
  # ApplicationController, so the require-login gate is enforced as a
  # routing constraint instead -- anonymous requests get a 404 (no
  # redirect, since this surface is intended for logged-in users only).
  constraints LoggedInConstraint do
    mount SolidQueueDashboard::Engine, at: "/jobs"
  end

  # `resource :freezer` defaults to FreezersController (Rails always
  # pluralises the controller class) but we have a singular FreezerController
  # because there's only ever one freezer per household. Force the lookup.
  resource :freezer, only: :show, controller: "freezer" do
    post :homemade
  end

  resource :bring_connection, only: %i[new create show update destroy] do
    post :sync
  end

  # --- REST API v1 ----------------------------------------------------------
  namespace :api do
    namespace :v1 do
      post "/sessions",   to: "sessions#create"
      delete "/sessions", to: "sessions#destroy"

      resources :products, only: %i[index show create update destroy] do
        collection { get :lookup } # GET /api/v1/products/lookup?barcode=...
        resources :prices, only: %i[index create update destroy]
      end
      resources :stores
      resources :storage_items
      resources :grocery_items do
        member { patch :purchase }
        collection { post :scan_purchase }
      end
      resources :receipts, only: %i[index create show destroy] do
        member do
          post :confirm
          post :reprocess
        end
      end

      # POST /api/v1/inbound_emails/poll          — drain all sources owned by the caller
      # POST /api/v1/inbound_emails/:id/poll      — drain one specific source
      # GET  /api/v1/inbound_emails                — list caller's sources + their health
      # Intended for external triggers (n8n, Home Assistant, anything
      # with an HTTP request node) — see Bearer token setup in
      # API docs / ApiToken model.
      resources :inbound_emails, only: %i[index], controller: "inbound_emails" do
        collection { post :poll }
        member     { post :poll }
      end
    end
  end

  # --- System ---------------------------------------------------------------
  get "/up", to: "rails/health#show", as: :rails_health_check
end

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

  # Tokened invite-acceptance flow (admins issue invites from /household; new
  # members set their name + password here). Public — reached while logged out.
  get   "/invitations/:token", to: "invitations#show",   as: :invitation
  patch "/invitations/:token", to: "invitations#update"

  # --- Web (Hotwire / ERB) --------------------------------------------------
  root to: "dashboard#index"

  # Path kept under `households/` (plural) for backward compatibility with
  # existing links and docs, even though the household itself is now a singular
  # resource at `/household`.
  resources :inbound_email_sources,
            only: %i[index new create edit update destroy],
            path: "households/inbound_emails"

  # Single household per instance: a singular resource for the household
  # settings page plus its member management. No index/switch/create/destroy --
  # the one household is created at first-run sign-up (see RegistrationsController)
  # and resolved everywhere via Household.current.
  resource :household, only: %i[show edit update] do
    resources :memberships, only: %i[create update destroy]
    resources :invitations, only: %i[destroy] # admin revoke of a pending invite
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
    collection do
      get  :scan      # Bulk barcode-scan add-to-storage kiosk
      post :scan_add  # Single scan -> create StorageItem; turbo-stream reply
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

  resources :todos do
    member do
      post   :transition # one-tap state change
      post   :follow
      delete :unfollow
    end
    resources :comments, only: %i[create destroy], controller: "todo_comments" do
      member do
        post :confirm_event      # turn a detected date into a calendar event (C5)
        post :dismiss_suggestion # never re-offer this comment's date
      end
    end
  end

  resources :notifications, only: %i[index] do
    member     { post :read }
    collection { post :read_all }
  end

  # Web Push subscription endpoints (browser posts subscription.toJSON()).
  post   "/push_subscriptions", to: "push_subscriptions#create",  as: :push_subscriptions
  delete "/push_subscriptions", to: "push_subscriptions#destroy"

  # Calendar (month/agenda/day via ?view=, navigated by ?date=).
  resource :calendar, only: :show, controller: "calendars"
  # External-calendar sync settings (admin-only) + Google OAuth flow.
  resource :calendar_connection, only: %i[show update] do
    post   :connect          # -> redirect to Google consent
    get    :callback         # Google redirects back here
    patch  :select_calendar  # choose which Google calendar to sync
    delete :disconnect
  end
  resources :calendar_events, only: %i[new create edit update destroy], path: "calendar/events" do
    member { post :create_todo } # make a todo from a task-like event (C7)
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

  # --- PWA ------------------------------------------------------------------
  # Manifest + Service Worker live at the document root so the SW's
  # default scope ("/") covers the entire app. The offline fallback is a
  # tiny standalone page the SW serves when a navigation request fails.
  get "/manifest.json",     to: "pwa#manifest",       as: :pwa_manifest
  get "/service-worker.js", to: "pwa#service_worker", as: :pwa_service_worker
  get "/offline",           to: "pwa#offline",        as: :pwa_offline

  # --- Android TWA ----------------------------------------------------------
  # Digital Asset Links file consumed by Chrome to confirm that the TWA
  # in android/ is owned by the operator of this domain. Required for
  # Chrome to hide the URL bar inside the installed Android app.
  get "/.well-known/assetlinks.json", to:       "well_known#assetlinks",
                                      as:       :well_known_assetlinks,
                                      defaults: { format: "json" }

  # --- System ---------------------------------------------------------------
  get "/up", to: "rails/health#show", as: :rails_health_check
end

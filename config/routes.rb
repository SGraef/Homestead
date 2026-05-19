# frozen_string_literal: true
# typed: ignore

Rails.application.routes.draw do
  # --- Auth (Sorcery) -------------------------------------------------------
  get  "/login",  to: "sessions#new",      as: :login
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
      patch :purchase   # mark as bought (typically called after a barcode scan)
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
  resources :offer_retailer_filters,  only: %i[create destroy], path: "offers/retailers"
  resources :offer_watchlist_entries, only: %i[create destroy], path: "offers/watchlist"
  resources :offer_categories, only: %i[index create update destroy], path: "offers/categories" do
    post :reset_defaults, on: :collection
    resources :offer_category_keywords, only: %i[create destroy], path: "keywords"
  end
  resources :manual_offers, only: %i[new create edit update destroy], path: "offers/manual"

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
    end
  end

  # --- System ---------------------------------------------------------------
  get "/up", to: "rails/health#show", as: :rails_health_check
end

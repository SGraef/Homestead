# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_01_01_000033) do
  create_table "active_storage_attachments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_tokens", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.string "name"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "bring_connections", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "bring_email", null: false
    t.string "bring_user_uuid", null: false
    t.string "default_list_uuid"
    t.string "default_list_name"
    t.string "access_token", limit: 1024
    t.string "refresh_token", limit: 1024
    t.datetime "access_token_expires_at"
    t.string "country_code", limit: 2, default: "DE"
    t.string "last_error", limit: 500
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "token_type", limit: 32, default: "Bearer"
    t.index ["household_id"], name: "index_bring_connections_on_household_id", unique: true
  end

  create_table "grocery_items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "product_id"
    t.bigint "store_id"
    t.decimal "quantity", precision: 12, scale: 3, default: "1.0", null: false
    t.string "status", default: "needed", null: false
    t.datetime "purchased_at"
    t.decimal "paid_amount_cents", precision: 12
    t.string "paid_currency", limit: 3
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", limit: 200
    t.index ["household_id", "status"], name: "index_grocery_items_on_household_id_and_status"
    t.index ["household_id"], name: "index_grocery_items_on_household_id"
    t.index ["product_id"], name: "index_grocery_items_on_product_id"
    t.index ["store_id"], name: "index_grocery_items_on_store_id"
  end

  create_table "households", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "postal_code", limit: 16
    t.integer "flaschenpost_warehouse_id"
  end

  create_table "inbound_email_sources", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "user_id", null: false
    t.string "label", limit: 80, null: false
    t.string "imap_host", null: false
    t.integer "imap_port", default: 993, null: false
    t.boolean "imap_ssl", default: true, null: false
    t.string "imap_username", null: false
    t.text "imap_password", null: false
    t.string "folder", default: "INBOX", null: false
    t.boolean "expunge", default: false, null: false
    t.datetime "last_polled_at"
    t.string "last_error", limit: 1000
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "imap_host", "imap_username", "folder"], name: "idx_inbound_email_sources_unique_per_household", unique: true
    t.index ["household_id"], name: "index_inbound_email_sources_on_household_id"
    t.index ["user_id"], name: "index_inbound_email_sources_on_user_id"
  end

  create_table "locations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "name", null: false
    t.string "kind", default: "other", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "kind"], name: "index_locations_on_household_id_and_kind"
    t.index ["household_id", "name"], name: "index_locations_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_locations_on_household_id"
  end

  create_table "meal_plan_entries", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "recipe_id", null: false
    t.date "planned_on", null: false
    t.string "slot", limit: 24, null: false
    t.decimal "servings", precision: 8, scale: 2, default: "1.0", null: false
    t.string "notes", limit: 200
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "planned_on", "slot"], name: "idx_meal_plan_household_date_slot"
    t.index ["household_id"], name: "index_meal_plan_entries_on_household_id"
    t.index ["recipe_id"], name: "index_meal_plan_entries_on_recipe_id"
  end

  create_table "memberships", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "household_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_memberships_on_household_id"
    t.index ["user_id", "household_id"], name: "index_memberships_on_user_id_and_household_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "offer_blocklist_entries", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "pattern", limit: 200, null: false
    t.string "reason", limit: 200
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "pattern"], name: "idx_offer_blocklist_household_pattern", unique: true
    t.index ["household_id"], name: "index_offer_blocklist_entries_on_household_id"
  end

  create_table "offer_categories", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "name", limit: 80, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "idx_offer_categories_household_name", unique: true
    t.index ["household_id", "position"], name: "idx_offer_categories_household_position"
    t.index ["household_id"], name: "index_offer_categories_on_household_id"
  end

  create_table "offer_category_keywords", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "offer_category_id", null: false
    t.string "keyword", limit: 80, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["offer_category_id", "keyword"], name: "idx_offer_category_keywords_cat_keyword", unique: true
    t.index ["offer_category_id"], name: "index_offer_category_keywords_on_offer_category_id"
  end

  create_table "offer_retailer_filters", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "retailer", limit: 80, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "retailer"], name: "idx_offer_retailer_filter_household_retailer", unique: true
    t.index ["household_id"], name: "index_offer_retailer_filters_on_household_id"
  end

  create_table "offer_watchlist_entries", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "pattern", limit: 200, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "pattern"], name: "idx_offer_watchlist_household_pattern", unique: true
    t.index ["household_id"], name: "index_offer_watchlist_entries_on_household_id"
  end

  create_table "offers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "product_id"
    t.bigint "store_id"
    t.string "source", limit: 32, default: "marktguru", null: false
    t.string "external_id", limit: 64, null: false
    t.string "retailer_name", limit: 80, null: false
    t.string "title", limit: 500, null: false
    t.string "brand", limit: 80
    t.string "category", limit: 80
    t.integer "price_cents", null: false
    t.integer "regular_price_cents"
    t.string "currency", limit: 8, default: "EUR", null: false
    t.string "unit", limit: 16
    t.text "quantity_text"
    t.text "image_url"
    t.text "source_url"
    t.date "valid_from"
    t.date "valid_until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "product_id"], name: "index_offers_on_household_id_and_product_id"
    t.index ["household_id", "source", "external_id"], name: "index_offers_on_household_id_and_source_and_external_id", unique: true
    t.index ["household_id", "valid_until"], name: "index_offers_on_household_id_and_valid_until"
    t.index ["household_id"], name: "index_offers_on_household_id"
    t.index ["product_id"], name: "index_offers_on_product_id"
    t.index ["store_id"], name: "index_offers_on_store_id"
  end

  create_table "prices", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "store_id", null: false
    t.decimal "amount_cents", precision: 12, null: false
    t.string "currency", limit: 3, default: "EUR", null: false
    t.date "observed_on", null: false
    t.string "source", default: "manual"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "pack_quantity", precision: 12, scale: 4, default: "1.0", null: false
    t.index ["product_id", "store_id", "observed_on"], name: "idx_prices_product_store_date"
    t.index ["product_id"], name: "index_prices_on_product_id"
    t.index ["store_id"], name: "index_prices_on_store_id"
  end

  create_table "product_barcodes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "barcode", null: false
    t.string "brand"
    t.string "quantity_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["barcode"], name: "index_product_barcodes_on_barcode"
    t.index ["product_id", "barcode"], name: "idx_product_barcodes_product_barcode", unique: true
    t.index ["product_id"], name: "index_product_barcodes_on_product_id"
  end

  create_table "product_synonyms", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "term", limit: 200, null: false
    t.string "normalized_term", limit: 200, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["normalized_term"], name: "index_product_synonyms_on_normalized_term"
    t.index ["product_id", "normalized_term"], name: "index_product_synonyms_on_product_id_and_normalized_term", unique: true
    t.index ["product_id"], name: "index_product_synonyms_on_product_id"
  end

  create_table "products", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "name", null: false
    t.string "brand"
    t.string "barcode"
    t.string "unit", default: "pcs", null: false
    t.string "category"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["barcode"], name: "index_products_on_barcode"
    t.index ["household_id", "barcode"], name: "idx_products_household_barcode", unique: true
    t.index ["household_id"], name: "index_products_on_household_id"
  end

  create_table "receipt_line_items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "receipt_id", null: false
    t.bigint "product_id"
    t.integer "position"
    t.string "line_text", limit: 1000
    t.string "parsed_name", limit: 200
    t.decimal "parsed_quantity", precision: 12, scale: 3, default: "1.0"
    t.bigint "parsed_unit_price_cents"
    t.bigint "parsed_total_cents"
    t.string "status", default: "unmatched", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_receipt_line_items_on_product_id"
    t.index ["receipt_id", "position"], name: "index_receipt_line_items_on_receipt_id_and_position"
    t.index ["receipt_id"], name: "index_receipt_line_items_on_receipt_id"
  end

  create_table "receipts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "store_id"
    t.bigint "user_id"
    t.string "status", default: "pending", null: false
    t.string "detected_store_name"
    t.text "raw_text", size: :medium
    t.string "error_message", limit: 1000
    t.date "purchased_on"
    t.bigint "subtotal_cents"
    t.string "currency", limit: 3, default: "EUR"
    t.datetime "parsed_at"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "status"], name: "index_receipts_on_household_id_and_status"
    t.index ["household_id"], name: "index_receipts_on_household_id"
    t.index ["store_id"], name: "index_receipts_on_store_id"
    t.index ["user_id"], name: "index_receipts_on_user_id"
  end

  create_table "recipe_ingredients", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "recipe_id", null: false
    t.bigint "product_id", null: false
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.string "unit", limit: 16
    t.string "notes", limit: 200
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_recipe_ingredients_on_product_id"
    t.index ["recipe_id", "position"], name: "index_recipe_ingredients_on_recipe_id_and_position"
    t.index ["recipe_id"], name: "index_recipe_ingredients_on_recipe_id"
  end

  create_table "recipes", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "name", limit: 200, null: false
    t.text "description"
    t.integer "servings", default: 1, null: false
    t.integer "prep_minutes"
    t.integer "cook_minutes"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "tags", limit: 500
    t.index ["household_id", "name"], name: "idx_recipes_household_name"
    t.index ["household_id"], name: "index_recipes_on_household_id"
  end

  create_table "solid_queue_blocked_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "storage_items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "product_id", null: false
    t.decimal "quantity", precision: 12, scale: 3, default: "1.0", null: false
    t.date "expires_on"
    t.date "opened_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "frozen_on"
    t.bigint "location_id", null: false
    t.index ["expires_on"], name: "index_storage_items_on_expires_on"
    t.index ["frozen_on"], name: "index_storage_items_on_frozen_on"
    t.index ["household_id", "product_id"], name: "idx_on_household_id_product_id_location_60d4add56f"
    t.index ["household_id"], name: "index_storage_items_on_household_id"
    t.index ["location_id"], name: "index_storage_items_on_location_id"
    t.index ["product_id"], name: "index_storage_items_on_product_id"
  end

  create_table "stores", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "name", null: false
    t.string "chain"
    t.string "address"
    t.string "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_stores_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_stores_on_household_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "email", null: false
    t.string "crypted_password"
    t.string "salt"
    t.string "name"
    t.string "remember_me_token"
    t.datetime "remember_me_token_expires_at"
    t.string "reset_password_token"
    t.datetime "reset_password_token_expires_at"
    t.datetime "reset_password_email_sent_at"
    t.integer "access_count_to_reset_password_page", default: 0
    t.string "activation_token"
    t.datetime "activation_token_expires_at"
    t.string "activation_state", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activation_token"], name: "index_users_on_activation_token"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["remember_me_token"], name: "index_users_on_remember_me_token"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "bring_connections", "households"
  add_foreign_key "grocery_items", "households"
  add_foreign_key "grocery_items", "products"
  add_foreign_key "grocery_items", "stores"
  add_foreign_key "inbound_email_sources", "households", on_delete: :cascade
  add_foreign_key "inbound_email_sources", "users", on_delete: :cascade
  add_foreign_key "locations", "households"
  add_foreign_key "meal_plan_entries", "households", on_delete: :cascade
  add_foreign_key "meal_plan_entries", "recipes", on_delete: :cascade
  add_foreign_key "memberships", "households"
  add_foreign_key "memberships", "users"
  add_foreign_key "offer_blocklist_entries", "households", on_delete: :cascade
  add_foreign_key "offer_categories", "households", on_delete: :cascade
  add_foreign_key "offer_category_keywords", "offer_categories", on_delete: :cascade
  add_foreign_key "offer_retailer_filters", "households", on_delete: :cascade
  add_foreign_key "offer_watchlist_entries", "households", on_delete: :cascade
  add_foreign_key "offers", "households", on_delete: :cascade
  add_foreign_key "offers", "products", on_delete: :nullify
  add_foreign_key "offers", "stores", on_delete: :nullify
  add_foreign_key "prices", "products"
  add_foreign_key "prices", "stores"
  add_foreign_key "product_barcodes", "products"
  add_foreign_key "product_synonyms", "products"
  add_foreign_key "products", "households"
  add_foreign_key "receipt_line_items", "products"
  add_foreign_key "receipt_line_items", "receipts"
  add_foreign_key "receipts", "households"
  add_foreign_key "receipts", "stores"
  add_foreign_key "receipts", "users"
  add_foreign_key "recipe_ingredients", "products", on_delete: :cascade
  add_foreign_key "recipe_ingredients", "recipes", on_delete: :cascade
  add_foreign_key "recipes", "households", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "storage_items", "households"
  add_foreign_key "storage_items", "locations"
  add_foreign_key "storage_items", "products"
  add_foreign_key "stores", "households"
end

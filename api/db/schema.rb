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

ActiveRecord::Schema[8.1].define(version: 2026_05_22_100001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_usage_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_summary"
    t.integer "input_tokens"
    t.string "model", null: false
    t.integer "output_tokens"
    t.string "status", default: "success", null: false
    t.string "task_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "task_type", "created_at"], name: "index_ai_usage_logs_on_user_id_and_task_type_and_created_at"
    t.index ["user_id"], name: "index_ai_usage_logs_on_user_id"
  end

  create_table "equipment_identifications", force: :cascade do |t|
    t.boolean "compatible"
    t.float "confidence"
    t.datetime "created_at", null: false
    t.string "equipment_name"
    t.bigint "exercise_id"
    t.string "image_checksum"
    t.string "localized_name"
    t.string "muscle_groups", default: [], array: true
    t.jsonb "raw_response"
    t.text "reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["exercise_id"], name: "index_equipment_identifications_on_exercise_id"
    t.index ["image_checksum"], name: "index_equipment_identifications_on_image_checksum"
    t.index ["user_id"], name: "index_equipment_identifications_on_user_id"
  end

  create_table "exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "difficulty", default: "intermediate"
    t.string "equipment_type", default: "gym", null: false
    t.string "exercise_type", default: "musculacao", null: false
    t.string "gif_url"
    t.boolean "home_compatible", default: false, null: false
    t.string "image_url"
    t.text "instructions"
    t.string "muscle_group"
    t.string "name"
    t.text "setup_guide"
    t.datetime "updated_at", null: false
    t.string "video_url"
    t.index ["equipment_type"], name: "index_exercises_on_equipment_type"
    t.index ["exercise_type"], name: "index_exercises_on_exercise_type"
  end

  create_table "health_data_points", force: :cascade do |t|
    t.text "ai_notes"
    t.datetime "collected_at"
    t.float "confidence"
    t.datetime "created_at", null: false
    t.string "field_name", null: false
    t.text "raw_text"
    t.string "source_type", null: false
    t.string "status", default: "pending_review", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "user_media_id"
    t.decimal "value", precision: 10, scale: 3
    t.index ["user_id", "field_name", "status"], name: "index_health_data_points_on_user_id_and_field_name_and_status"
    t.index ["user_id"], name: "index_health_data_points_on_user_id"
    t.index ["user_media_id"], name: "index_health_data_points_on_user_media_id"
  end

  create_table "health_profiles", force: :cascade do |t|
    t.text "activity_preferences", default: [], array: true
    t.integer "age"
    t.string "cardio_format"
    t.string "cardio_type"
    t.datetime "created_at", null: false
    t.jsonb "custom_splits", default: []
    t.string "fitness_level"
    t.string "goal"
    t.decimal "height_cm"
    t.string "modality", default: "ai_choice"
    t.string "split_type", default: "ai_choice"
    t.integer "training_days_per_week", default: 3
    t.string "training_location", default: "gym", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.decimal "weight_kg"
    t.index ["user_id"], name: "index_health_profiles_on_user_id"
  end

  create_table "stripe_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_type"
    t.datetime "processed_at", null: false
    t.string "status", default: "processed", null: false
    t.string "stripe_event_id", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_event_id"], name: "index_stripe_events_on_stripe_event_id", unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.boolean "cancel_at_period_end", default: false, null: false
    t.datetime "canceled_at"
    t.datetime "created_at", null: false
    t.datetime "current_period_end"
    t.datetime "current_period_start"
    t.string "plan_name", default: "pro_monthly", null: false
    t.string "status", default: "incomplete", null: false
    t.string "stripe_customer_id"
    t.string "stripe_price_id"
    t.string "stripe_subscription_id"
    t.datetime "trial_end"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["stripe_customer_id"], name: "index_subscriptions_on_stripe_customer_id"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true
    t.index ["user_id"], name: "index_subscriptions_on_user_id", unique: true
  end

  create_table "user_media", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "category"], name: "index_user_media_on_user_id_and_category"
    t.index ["user_id"], name: "index_user_media_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "anonymized_at"
    t.datetime "created_at", null: false
    t.datetime "deletion_requested_at"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "first_workout_completed_at"
    t.boolean "free_workout_used", default: false, null: false
    t.string "name", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "reset_password_token_digest"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workout_day_exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_minutes"
    t.bigint "exercise_id", null: false
    t.string "intensity"
    t.integer "order_index"
    t.integer "reps"
    t.integer "rest_seconds"
    t.integer "sets"
    t.datetime "updated_at", null: false
    t.bigint "workout_day_id", null: false
    t.index ["exercise_id"], name: "index_workout_day_exercises_on_exercise_id"
    t.index ["workout_day_id"], name: "index_workout_day_exercises_on_workout_day_id"
  end

  create_table "workout_days", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "day_of_week"
    t.string "name"
    t.integer "position"
    t.datetime "updated_at", null: false
    t.bigint "workout_plan_id", null: false
    t.index ["workout_plan_id"], name: "index_workout_days_on_workout_plan_id"
  end

  create_table "workout_plans", force: :cascade do |t|
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_workout_plans_on_user_id"
  end

  create_table "workout_sessions", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_minutes"
    t.jsonb "exercise_logs", default: [], null: false
    t.integer "fatigue_level"
    t.text "notes"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_day_id", null: false
    t.index ["user_id"], name: "index_workout_sessions_on_user_id"
    t.index ["workout_day_id"], name: "index_workout_sessions_on_workout_day_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_usage_logs", "users"
  add_foreign_key "equipment_identifications", "exercises"
  add_foreign_key "equipment_identifications", "users"
  add_foreign_key "health_data_points", "user_media", column: "user_media_id"
  add_foreign_key "health_data_points", "users"
  add_foreign_key "health_profiles", "users"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "user_media", "users"
  add_foreign_key "workout_day_exercises", "exercises"
  add_foreign_key "workout_day_exercises", "workout_days"
  add_foreign_key "workout_days", "workout_plans"
  add_foreign_key "workout_plans", "users"
  add_foreign_key "workout_sessions", "users"
  add_foreign_key "workout_sessions", "workout_days"
end

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

ActiveRecord::Schema[8.1].define(version: 2026_06_21_222519) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

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

  create_table "ai_chat_messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "role", null: false
    t.string "session_id", null: false
    t.string "source", default: "rag", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["created_at"], name: "index_ai_chat_messages_on_created_at"
    t.index ["session_id"], name: "index_ai_chat_messages_on_session_id"
    t.index ["user_id", "created_at"], name: "index_ai_chat_messages_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_ai_chat_messages_on_user_id"
  end

  create_table "ai_prompt_versions", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "prompt_type", null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["active"], name: "index_ai_prompt_versions_on_active"
    t.index ["name", "version"], name: "index_ai_prompt_versions_on_name_and_version", unique: true
  end

  create_table "ai_training_decision_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.decimal "estimated_cost_cents", precision: 10, scale: 6
    t.string "generation_type", default: "workout_plan"
    t.jsonb "input_summary", default: {}
    t.string "model_used"
    t.jsonb "output_summary", default: {}
    t.text "progression_strategy"
    t.bigint "prompt_version_id"
    t.text "rationale"
    t.jsonb "safety_notes", default: []
    t.string "status", default: "success"
    t.integer "tokens_input"
    t.integer "tokens_output"
    t.string "training_method"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.jsonb "week_structure", default: []
    t.bigint "workout_plan_id", null: false
    t.index ["prompt_version_id"], name: "index_ai_training_decision_logs_on_prompt_version_id"
    t.index ["status"], name: "index_ai_training_decision_logs_on_status"
    t.index ["user_id", "created_at"], name: "index_ai_training_decision_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_ai_training_decision_logs_on_user_id"
    t.index ["workout_plan_id"], name: "index_ai_training_decision_logs_on_workout_plan_id"
  end

  create_table "ai_usage_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_summary"
    t.integer "estimated_cost_cents"
    t.integer "input_tokens"
    t.string "model", null: false
    t.integer "output_tokens"
    t.string "provider", default: "anthropic", null: false
    t.string "status", default: "success", null: false
    t.string "task_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "provider", "created_at"], name: "index_ai_usage_logs_on_user_provider_created"
    t.index ["user_id", "task_type", "created_at"], name: "index_ai_usage_logs_on_user_id_and_task_type_and_created_at"
    t.index ["user_id"], name: "index_ai_usage_logs_on_user_id"
  end

  create_table "client_permissions", force: :cascade do |t|
    t.boolean "can_view_adherence", default: true, null: false
    t.boolean "can_view_assigned_workouts", default: true, null: false
    t.boolean "can_view_body_analysis", default: false, null: false
    t.boolean "can_view_body_weight", default: false, null: false
    t.boolean "can_view_completed_workouts", default: true, null: false
    t.boolean "can_view_exams", default: false, null: false
    t.boolean "can_view_exercise_performance", default: false, null: false
    t.boolean "can_view_photos", default: false, null: false
    t.datetime "created_at", null: false
    t.bigint "personal_client_relationship_id", null: false
    t.datetime "updated_at", null: false
    t.index ["personal_client_relationship_id"], name: "index_client_permissions_on_personal_client_relationship_id", unique: true
  end

  create_table "coach_insights", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "fitness_profile_id", null: false
    t.string "insight_type", null: false
    t.text "message", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "read_at"
    t.string "severity", default: "info", null: false
    t.string "source", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["fitness_profile_id"], name: "index_coach_insights_on_fitness_profile_id"
    t.index ["insight_type"], name: "index_coach_insights_on_insight_type"
    t.index ["user_id", "created_at"], name: "index_coach_insights_on_user_id_and_created_at"
    t.index ["user_id", "read_at"], name: "index_coach_insights_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_coach_insights_on_user_id"
  end

  create_table "community_comments", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "community_post_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["community_post_id", "created_at"], name: "index_community_comments_on_community_post_id_and_created_at"
    t.index ["community_post_id"], name: "index_community_comments_on_community_post_id"
    t.index ["user_id"], name: "index_community_comments_on_user_id"
  end

  create_table "community_posts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.jsonb "metadata", default: {}
    t.string "post_type", null: false
    t.string "title"
    t.bigint "user_id", null: false
    t.string "visibility", default: "public", null: false
    t.index ["user_id", "created_at"], name: "index_community_posts_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_community_posts_on_user_id"
    t.index ["visibility"], name: "index_community_posts_on_visibility"
  end

  create_table "community_reactions", force: :cascade do |t|
    t.bigint "community_post_id", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "reaction_type", default: "congrats", null: false
    t.bigint "user_id", null: false
    t.index ["community_post_id"], name: "index_community_reactions_on_community_post_id"
    t.index ["user_id", "community_post_id"], name: "index_community_reactions_on_user_id_and_community_post_id", unique: true
    t.index ["user_id"], name: "index_community_reactions_on_user_id"
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

  create_table "exercise_suggestion_logs", force: :cascade do |t|
    t.boolean "accepted"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "current_exercise_id"
    t.string "event_type", null: false
    t.text "intent_text"
    t.jsonb "parsed_intent", default: {}
    t.integer "score"
    t.integer "suggested_exercise_id"
    t.bigint "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_exercise_suggestion_logs_on_user_id_and_created_at"
    t.index ["user_id", "suggested_exercise_id"], name: "idx_on_user_id_suggested_exercise_id_dfd3213d7b"
    t.index ["user_id"], name: "index_exercise_suggestion_logs_on_user_id"
  end

  create_table "exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "difficulty", default: "intermediate"
    t.string "difficulty_level"
    t.string "equipment_type", default: "gym", null: false
    t.string "exercise_type", default: "musculacao", null: false
    t.string "gif_path"
    t.string "gif_url"
    t.boolean "home_compatible", default: false, null: false
    t.string "image_fallback_url"
    t.string "image_url"
    t.text "instructions"
    t.string "muscle_group"
    t.string "name"
    t.string "name_en"
    t.text "safety_tags", default: [], null: false, array: true
    t.text "setup_guide"
    t.string "source_dataset"
    t.datetime "updated_at", null: false
    t.string "video_url"
    t.index ["difficulty_level"], name: "index_exercises_on_difficulty_level"
    t.index ["equipment_type"], name: "index_exercises_on_equipment_type"
    t.index ["exercise_type"], name: "index_exercises_on_exercise_type"
  end

  create_table "fitness_profiles", force: :cascade do |t|
    t.decimal "adherence_score", precision: 4, scale: 2, default: "0.0", null: false
    t.jsonb "available_equipment", default: [], null: false
    t.jsonb "avoided_exercises", default: [], null: false
    t.decimal "behavior_confidence_score", precision: 4, scale: 2, default: "0.0", null: false
    t.string "behavior_pattern", default: "unknown", null: false
    t.string "classification_version", default: "v1", null: false
    t.decimal "consistency_score", precision: 4, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "current_goal"
    t.string "current_phase", default: "onboarding", null: false
    t.string "fitness_level", default: "beginner", null: false
    t.datetime "last_recalculated_at"
    t.jsonb "metadata", default: {}, null: false
    t.decimal "mobility_score", precision: 4, scale: 2, default: "0.0", null: false
    t.decimal "motivation_score", precision: 4, scale: 2, default: "0.0", null: false
    t.jsonb "physical_limitations", default: [], null: false
    t.decimal "preference_confidence_score", precision: 4, scale: 2, default: "0.0", null: false
    t.jsonb "preferred_body_focus", default: [], null: false
    t.jsonb "preferred_exercises", default: [], null: false
    t.jsonb "preferred_training_styles", default: [], null: false
    t.string "primary_persona", default: "general_health", null: false
    t.decimal "recovery_score", precision: 4, scale: 2, default: "0.0", null: false
    t.decimal "risk_score", precision: 4, scale: 2, default: "0.0", null: false
    t.string "secondary_persona"
    t.string "secondary_training_archetype"
    t.string "training_archetype", default: "balanced_full_body", null: false
    t.decimal "training_maturity", precision: 4, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_fitness_profiles_on_user_id", unique: true
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
    t.decimal "adherence_score", precision: 5, scale: 2
    t.integer "age"
    t.text "available_equipment", default: [], null: false, array: true
    t.bigint "avoided_exercise_ids", default: [], null: false, array: true
    t.string "cardio_format"
    t.string "cardio_type"
    t.datetime "created_at", null: false
    t.jsonb "custom_splits", default: []
    t.string "fitness_level"
    t.string "gender"
    t.string "goal"
    t.decimal "height_cm"
    t.string "intensity_preference"
    t.datetime "last_profile_review_at"
    t.text "limitations", default: [], array: true
    t.string "modality", default: "ai_choice"
    t.text "preferred_body_focus", default: [], null: false, array: true
    t.text "preferred_training_styles", default: [], array: true
    t.integer "session_duration_minutes"
    t.string "split_type", default: "ai_choice"
    t.string "training_context"
    t.integer "training_days_per_week", default: 3
    t.string "training_location", default: "full_gym", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.decimal "weight_kg"
    t.index ["user_id"], name: "index_health_profiles_on_user_id"
  end

# Could not dump table "knowledge_chunks" because of following StandardError
#   Unknown type 'vector(1536)' for column 'embedding'


  create_table "knowledge_documents", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "category", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "source"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_knowledge_documents_on_active"
    t.index ["category"], name: "index_knowledge_documents_on_category"
    t.index ["source"], name: "index_knowledge_documents_on_source", unique: true
  end

  create_table "personal_alerts", force: :cascade do |t|
    t.text "body"
    t.bigint "client_id"
    t.datetime "created_at", null: false
    t.string "kind", default: "info", null: false
    t.bigint "personal_id", null: false
    t.datetime "read_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_personal_alerts_on_client_id"
    t.index ["personal_id", "read_at"], name: "index_personal_alerts_on_personal_id_and_read_at"
    t.index ["personal_id"], name: "index_personal_alerts_on_personal_id"
  end

  create_table "personal_client_relationships", force: :cascade do |t|
    t.bigint "client_id"
    t.datetime "created_at", null: false
    t.string "invitation_code", null: false
    t.datetime "invitation_expires_at"
    t.datetime "invitation_sent_at"
    t.bigint "personal_id", null: false
    t.datetime "started_at"
    t.string "status", default: "invited", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_personal_client_relationships_on_client_id"
    t.index ["invitation_code"], name: "index_personal_client_relationships_on_invitation_code", unique: true
    t.index ["personal_id", "client_id"], name: "index_pcr_on_personal_and_client_active", unique: true, where: "((client_id IS NOT NULL) AND ((status)::text <> 'removed'::text))"
    t.index ["personal_id"], name: "index_personal_client_relationships_on_personal_id"
    t.index ["status"], name: "index_personal_client_relationships_on_status"
  end

  create_table "personal_notes", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.bigint "personal_id", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "private", null: false
    t.index ["personal_id", "client_id"], name: "index_personal_notes_on_personal_id_and_client_id"
    t.index ["personal_id"], name: "index_personal_notes_on_personal_id"
  end

  create_table "public_profiles", force: :cascade do |t|
    t.boolean "avatar_visible", default: false, null: false
    t.boolean "city_visible", default: false, null: false
    t.boolean "country_visible", default: false, null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.text "public_bio"
    t.boolean "show_badges", default: false, null: false
    t.boolean "show_points", default: false, null: false
    t.boolean "show_progress_photos", default: false, null: false
    t.boolean "show_streak", default: true, null: false
    t.boolean "show_workout_count", default: true, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_public_profiles_on_user_id", unique: true
  end

  create_table "shared_workouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.boolean "include_notes", default: false, null: false
    t.boolean "include_weights", default: false, null: false
    t.bigint "owner_id", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.string "title"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "view_count", default: 0, null: false
    t.string "visibility", default: "private_link", null: false
    t.index ["owner_id"], name: "index_shared_workouts_on_owner_id"
    t.index ["token"], name: "index_shared_workouts_on_token", unique: true
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

  create_table "trainer_profiles", force: :cascade do |t|
    t.text "bio"
    t.datetime "created_at", null: false
    t.string "cref"
    t.string "display_name"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_trainer_profiles_on_user_id", unique: true
  end

  create_table "user_badges", force: :cascade do |t|
    t.string "badge_key", null: false
    t.datetime "created_at", null: false
    t.datetime "earned_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "badge_key"], name: "index_user_badges_on_user_id_and_badge_key", unique: true
    t.index ["user_id"], name: "index_user_badges_on_user_id"
  end

  create_table "user_events", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "event_name", null: false
    t.jsonb "metadata", default: {}
    t.bigint "user_id", null: false
    t.index ["event_name", "created_at"], name: "index_user_events_on_event_name_and_created_at"
    t.index ["user_id", "event_name"], name: "index_user_events_on_user_id_and_event_name"
    t.index ["user_id"], name: "index_user_events_on_user_id"
  end

  create_table "user_favorite_exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "exercise_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["exercise_id"], name: "index_user_favorite_exercises_on_exercise_id"
    t.index ["user_id", "exercise_id"], name: "index_user_favorite_exercises_on_user_id_and_exercise_id", unique: true
    t.index ["user_id"], name: "index_user_favorite_exercises_on_user_id"
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

  create_table "user_training_preferences", force: :cascade do |t|
    t.decimal "confidence", precision: 3, scale: 2, default: "1.0"
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "last_seen_at"
    t.string "source"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "value", null: false
    t.index ["user_id", "key"], name: "index_user_training_preferences_on_user_id_and_key", unique: true
    t.index ["user_id"], name: "index_user_training_preferences_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "account_type", default: "regular", null: false
    t.boolean "admin", default: false, null: false
    t.datetime "anonymized_at"
    t.boolean "community_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "deletion_requested_at"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "first_workout_completed_at"
    t.boolean "free_workout_used", default: false, null: false
    t.string "name", default: "", null: false
    t.string "profile_visibility", default: "private", null: false
    t.string "provider"
    t.string "referral_code"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "reset_password_token_digest"
    t.datetime "trial_ends_at"
    t.datetime "trial_started_at"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["account_type"], name: "index_users_on_account_type"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["referral_code"], name: "index_users_on_referral_code", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["trial_ends_at"], name: "index_users_on_trial_ends_at"
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
    t.string "custom_name"
    t.integer "day_of_week"
    t.boolean "favorited", default: false, null: false
    t.string "invalid_workout_reason"
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
    t.integer "calories_estimated"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_minutes"
    t.jsonb "exercise_logs", default: [], null: false
    t.integer "fatigue_level"
    t.text "notes"
    t.string "source"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_day_id"
    t.index ["user_id"], name: "index_workout_sessions_on_user_id"
    t.index ["workout_day_id"], name: "index_workout_sessions_on_workout_day_id"
  end

  create_table "workout_strategies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "fitness_profile_id"
    t.jsonb "strategy", default: {}, null: false
    t.string "strategy_version", default: "v1", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_plan_id", null: false
    t.index ["fitness_profile_id"], name: "index_workout_strategies_on_fitness_profile_id"
    t.index ["user_id"], name: "index_workout_strategies_on_user_id"
    t.index ["workout_plan_id"], name: "index_workout_strategies_on_workout_plan_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_chat_messages", "users"
  add_foreign_key "ai_training_decision_logs", "ai_prompt_versions", column: "prompt_version_id"
  add_foreign_key "ai_training_decision_logs", "users"
  add_foreign_key "ai_training_decision_logs", "workout_plans"
  add_foreign_key "ai_usage_logs", "users"
  add_foreign_key "client_permissions", "personal_client_relationships"
  add_foreign_key "coach_insights", "fitness_profiles"
  add_foreign_key "coach_insights", "users"
  add_foreign_key "community_comments", "community_posts"
  add_foreign_key "community_comments", "users"
  add_foreign_key "community_posts", "users"
  add_foreign_key "community_reactions", "community_posts"
  add_foreign_key "community_reactions", "users"
  add_foreign_key "equipment_identifications", "exercises"
  add_foreign_key "equipment_identifications", "users"
  add_foreign_key "exercise_suggestion_logs", "users"
  add_foreign_key "fitness_profiles", "users"
  add_foreign_key "health_data_points", "user_media", column: "user_media_id"
  add_foreign_key "health_data_points", "users"
  add_foreign_key "health_profiles", "users"
  add_foreign_key "knowledge_chunks", "knowledge_documents"
  add_foreign_key "personal_alerts", "users", column: "client_id"
  add_foreign_key "personal_alerts", "users", column: "personal_id"
  add_foreign_key "personal_client_relationships", "users", column: "client_id"
  add_foreign_key "personal_client_relationships", "users", column: "personal_id"
  add_foreign_key "personal_notes", "users", column: "client_id"
  add_foreign_key "personal_notes", "users", column: "personal_id"
  add_foreign_key "public_profiles", "users"
  add_foreign_key "shared_workouts", "users", column: "owner_id"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "trainer_profiles", "users"
  add_foreign_key "user_badges", "users"
  add_foreign_key "user_events", "users"
  add_foreign_key "user_favorite_exercises", "exercises"
  add_foreign_key "user_favorite_exercises", "users"
  add_foreign_key "user_media", "users"
  add_foreign_key "user_training_preferences", "users"
  add_foreign_key "workout_day_exercises", "exercises"
  add_foreign_key "workout_day_exercises", "workout_days"
  add_foreign_key "workout_days", "workout_plans"
  add_foreign_key "workout_plans", "users"
  add_foreign_key "workout_sessions", "users"
  add_foreign_key "workout_sessions", "workout_days"
  add_foreign_key "workout_strategies", "fitness_profiles"
  add_foreign_key "workout_strategies", "users"
  add_foreign_key "workout_strategies", "workout_plans"
end

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

ActiveRecord::Schema[8.1].define(version: 2026_07_15_120003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "unaccent"
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
    t.string "decision_source", default: "ai", null: false
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
    t.index ["decision_source"], name: "index_ai_training_decision_logs_on_decision_source"
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

  create_table "ai_workout_chat_conversations", force: :cascade do |t|
    t.jsonb "collected_profile", default: {}, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "follow_up_rounds", default: 0, null: false
    t.jsonb "generated_preview"
    t.jsonb "guardrail_flags", default: {}, null: false
    t.jsonb "messages", default: [], null: false
    t.string "status", default: "collecting", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_plan_id"
    t.index ["user_id", "status"], name: "index_ai_workout_chat_conversations_on_user_id_and_status"
    t.index ["user_id"], name: "index_ai_workout_chat_conversations_on_user_id"
    t.index ["workout_plan_id"], name: "index_ai_workout_chat_conversations_on_workout_plan_id"
  end

  create_table "analytics_experiment_assignments", force: :cascade do |t|
    t.string "anonymous_id"
    t.datetime "assigned_at", null: false
    t.datetime "converted_at"
    t.datetime "created_at", null: false
    t.string "experiment_key", null: false
    t.datetime "exposed_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "variant", null: false
    t.index ["experiment_key", "anonymous_id"], name: "index_analytics_experiments_unique_anon", unique: true, where: "((user_id IS NULL) AND (anonymous_id IS NOT NULL))"
    t.index ["experiment_key", "user_id"], name: "index_analytics_experiments_unique_user", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["experiment_key", "variant"], name: "idx_on_experiment_key_variant_60f2dbba2f"
    t.index ["user_id"], name: "index_analytics_experiment_assignments_on_user_id"
  end

  create_table "blocked_emails", force: :cascade do |t|
    t.datetime "blocked_at", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["email"], name: "index_blocked_emails_on_email", unique: true
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

  create_table "coach_recommendations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.decimal "confidence", precision: 4, scale: 2
    t.datetime "created_at", null: false
    t.decimal "current_value", precision: 6, scale: 2
    t.datetime "dismissed_at"
    t.bigint "exercise_id"
    t.string "exercise_name"
    t.text "message"
    t.jsonb "metadata", default: {}
    t.jsonb "reasons", default: []
    t.string "recommendation_type", null: false
    t.decimal "recommended_value", precision: 6, scale: 2
    t.string "status", default: "pending", null: false
    t.string "title"
    t.string "unit"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["exercise_id"], name: "index_coach_recommendations_on_exercise_id"
    t.index ["user_id", "exercise_id", "recommendation_type", "status"], name: "idx_coach_recs_unique_pending"
    t.index ["user_id", "status"], name: "index_coach_recommendations_on_user_id_and_status"
    t.index ["user_id"], name: "index_coach_recommendations_on_user_id"
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

  create_table "device_tokens", force: :cascade do |t|
    t.string "app_version"
    t.datetime "created_at", null: false
    t.string "device_identifier"
    t.boolean "enabled", default: true, null: false
    t.datetime "invalidated_at"
    t.string "invalidation_reason"
    t.datetime "last_seen_at"
    t.string "os_version"
    t.string "permission_status"
    t.string "platform", default: "android", null: false
    t.string "token", null: false
    t.datetime "token_refreshed_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["enabled"], name: "index_device_tokens_on_enabled"
    t.index ["invalidated_at"], name: "index_device_tokens_on_invalidated_at"
    t.index ["token"], name: "index_device_tokens_on_token", unique: true
    t.index ["user_id", "platform"], name: "index_device_tokens_on_user_id_and_platform"
    t.index ["user_id"], name: "index_device_tokens_on_user_id"
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

  create_table "exercise_sessions", force: :cascade do |t|
    t.string "avg_pace_per_km"
    t.decimal "avg_speed_kmh", precision: 5, scale: 2
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.decimal "distance_km", precision: 6, scale: 2
    t.integer "duration_minutes"
    t.integer "elapsed_seconds"
    t.bigint "exercise_id", null: false
    t.string "exercise_kind", default: "strength", null: false
    t.string "feeling"
    t.string "intensity"
    t.integer "order_index", null: false
    t.integer "planned_reps"
    t.integer "planned_sets"
    t.decimal "planned_weight_kg", precision: 6, scale: 2
    t.integer "rest_seconds"
    t.integer "round_number", default: 1, null: false
    t.datetime "started_at", null: false
    t.string "status", default: "in_progress", null: false
    t.integer "target_seconds"
    t.datetime "updated_at", null: false
    t.bigint "workout_block_id"
    t.bigint "workout_day_exercise_id"
    t.bigint "workout_session_id", null: false
    t.index ["exercise_id", "status"], name: "index_exercise_sessions_on_exercise_id_and_status"
    t.index ["exercise_id"], name: "index_exercise_sessions_on_exercise_id"
    t.index ["workout_block_id"], name: "index_exercise_sessions_on_workout_block_id"
    t.index ["workout_day_exercise_id"], name: "index_exercise_sessions_on_workout_day_exercise_id"
    t.index ["workout_session_id"], name: "index_exercise_sessions_on_workout_session_id"
  end

  create_table "exercise_sets", force: :cascade do |t|
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.bigint "exercise_session_id", null: false
    t.boolean "is_warmup", default: false, null: false
    t.integer "reps"
    t.integer "set_number", null: false
    t.datetime "updated_at", null: false
    t.decimal "weight_kg", precision: 6, scale: 2
    t.index ["exercise_session_id", "set_number"], name: "idx_exercise_sets_unique_set_number", unique: true
    t.index ["exercise_session_id"], name: "index_exercise_sets_on_exercise_session_id"
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
    t.string "calisthenics_skill"
    t.boolean "compound"
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
    t.string "movement_pattern"
    t.string "muscle_group"
    t.string "name"
    t.string "name_en"
    t.text "objective_tags", default: [], null: false, array: true
    t.bigint "regression_exercise_id"
    t.boolean "requires_barbell_skill", default: false, null: false
    t.boolean "requires_bodyweight_strength", default: false, null: false
    t.string "risk_level"
    t.text "safety_tags", default: [], null: false, array: true
    t.text "setup_guide"
    t.string "source_dataset"
    t.text "style_tags", default: [], null: false, array: true
    t.string "technical_complexity"
    t.boolean "unilateral", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "video_url"
    t.index ["calisthenics_skill"], name: "index_exercises_on_calisthenics_skill"
    t.index ["difficulty_level"], name: "index_exercises_on_difficulty_level"
    t.index ["equipment_type"], name: "index_exercises_on_equipment_type"
    t.index ["exercise_type"], name: "index_exercises_on_exercise_type"
    t.index ["muscle_group"], name: "index_exercises_on_muscle_group"
    t.index ["regression_exercise_id"], name: "index_exercises_on_regression_exercise_id"
    t.index ["risk_level"], name: "index_exercises_on_risk_level"
    t.index ["technical_complexity"], name: "index_exercises_on_technical_complexity"
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
    t.jsonb "muscle_priorities", default: {}
    t.text "preferred_body_focus", default: [], null: false, array: true
    t.text "preferred_training_styles", default: [], array: true
    t.string "preferred_workout_period"
    t.time "preferred_workout_time"
    t.datetime "preferred_workout_time_updated_at"
    t.jsonb "profiling_prompts_answered", default: {}, null: false
    t.text "selected_muscle_groups", default: [], array: true
    t.integer "session_duration_minutes"
    t.string "split_type", default: "ai_choice"
    t.string "training_context"
    t.integer "training_days_per_week", default: 3
    t.string "training_location", default: "full_gym", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.decimal "weight_kg"
    t.string "workout_time_source"
    t.index ["user_id"], name: "index_health_profiles_on_user_id"
  end

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

  create_table "mobile_auth_codes", force: :cascade do |t|
    t.string "code_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "platform", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.bigint "user_id", null: false
    t.index ["code_digest"], name: "index_mobile_auth_codes_on_code_digest", unique: true
    t.index ["platform", "expires_at"], name: "index_mobile_auth_codes_on_platform_and_expires_at"
    t.index ["user_id", "used_at"], name: "index_mobile_auth_codes_on_user_id_and_used_at"
    t.index ["user_id"], name: "index_mobile_auth_codes_on_user_id"
  end

  create_table "notification_deliveries", force: :cascade do |t|
    t.string "cancel_reason"
    t.datetime "canceled_at"
    t.datetime "clicked_at"
    t.datetime "converted_at"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "error_code"
    t.string "idempotency_key"
    t.string "notification_type", null: false
    t.datetime "opened_at"
    t.jsonb "payload_json", default: {}, null: false
    t.string "provider_message_id"
    t.bigint "push_device_id"
    t.integer "retry_count", default: 0, null: false
    t.datetime "scheduled_for"
    t.datetime "sent_at"
    t.string "status", default: "scheduled", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["idempotency_key"], name: "index_notification_deliveries_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["push_device_id"], name: "index_notification_deliveries_on_push_device_id"
    t.index ["scheduled_for"], name: "index_notification_deliveries_on_scheduled_for"
    t.index ["status"], name: "index_notification_deliveries_on_status"
    t.index ["user_id", "notification_type"], name: "index_notification_deliveries_on_user_id_and_notification_type"
    t.index ["user_id"], name: "index_notification_deliveries_on_user_id"
  end

  create_table "onboarding_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_name", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.string "onboarding_flow"
    t.string "step_name"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_name", "occurred_at"], name: "index_onboarding_events_on_event_name_and_occurred_at"
    t.index ["event_name"], name: "index_onboarding_events_on_event_name"
    t.index ["occurred_at"], name: "index_onboarding_events_on_occurred_at"
    t.index ["onboarding_flow", "event_name"], name: "index_onboarding_events_on_onboarding_flow_and_event_name"
    t.index ["onboarding_flow"], name: "index_onboarding_events_on_onboarding_flow"
    t.index ["step_name"], name: "index_onboarding_events_on_step_name"
    t.index ["user_id"], name: "index_onboarding_events_on_user_id"
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

  create_table "product_analytics_events", force: :cascade do |t|
    t.string "anonymous_id"
    t.string "app_surface", default: "unknown", null: false
    t.string "app_version"
    t.string "build_number"
    t.datetime "created_at", null: false
    t.string "environment", default: "production", null: false
    t.string "event_name", null: false
    t.integer "event_version", default: 1, null: false
    t.string "idempotency_key"
    t.string "locale"
    t.datetime "occurred_at", null: false
    t.string "platform", default: "unknown", null: false
    t.jsonb "properties", default: {}, null: false
    t.datetime "received_at", null: false
    t.string "session_id"
    t.string "source"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["anonymous_id"], name: "index_product_analytics_events_on_anonymous_id"
    t.index ["event_name", "occurred_at"], name: "index_product_analytics_events_on_event_name_and_occurred_at"
    t.index ["idempotency_key"], name: "index_product_analytics_events_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["platform", "occurred_at"], name: "index_product_analytics_events_on_platform_and_occurred_at"
    t.index ["user_id", "occurred_at"], name: "index_product_analytics_events_on_user_id_and_occurred_at"
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

  create_table "relationship_messages", force: :cascade do |t|
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_name", null: false
    t.datetime "failed_at"
    t.string "idempotency_key"
    t.string "journey_key"
    t.jsonb "metadata_json", default: {}
    t.string "provider", null: false
    t.string "provider_message_id"
    t.jsonb "provider_response_json", default: {}
    t.string "recipient_email"
    t.datetime "sent_at"
    t.datetime "skipped_at"
    t.string "status", default: "pending", null: false
    t.string "step_key"
    t.string "subject"
    t.string "template_key"
    t.datetime "updated_at", null: false
    t.bigint "user_event_id"
    t.bigint "user_id", null: false
    t.index ["event_name"], name: "index_relationship_messages_on_event_name"
    t.index ["idempotency_key"], name: "index_relationship_messages_on_idempotency_key", unique: true
    t.index ["journey_key"], name: "index_relationship_messages_on_journey_key"
    t.index ["provider_message_id"], name: "index_relationship_messages_on_provider_message_id"
    t.index ["status"], name: "index_relationship_messages_on_status"
    t.index ["template_key"], name: "index_relationship_messages_on_template_key"
    t.index ["user_event_id"], name: "index_relationship_messages_on_user_event_id"
    t.index ["user_id"], name: "index_relationship_messages_on_user_id"
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
    t.string "idempotency_key"
    t.integer "make_attempts_count", default: 0, null: false
    t.string "make_delivery_status", default: "disabled", null: false
    t.datetime "make_last_attempt_at"
    t.text "make_last_error"
    t.jsonb "metadata", default: {}
    t.datetime "occurred_at", null: false
    t.jsonb "payload_json", default: {}, null: false
    t.string "source", default: "easyhealth_backend", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_name", "created_at"], name: "index_user_events_on_event_name_and_created_at"
    t.index ["idempotency_key"], name: "index_user_events_on_idempotency_key"
    t.index ["make_delivery_status", "created_at"], name: "index_user_events_on_make_status_and_created_at"
    t.index ["user_id", "event_name", "idempotency_key"], name: "index_user_events_on_user_event_idempotency", unique: true, where: "(idempotency_key IS NOT NULL)"
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

  create_table "user_notification_preferences", force: :cascade do |t|
    t.datetime "activation_notifications_completed_at"
    t.string "activation_push_variant"
    t.datetime "activation_recovery_sent_at"
    t.datetime "activation_reminder_sent_at"
    t.datetime "created_at", null: false
    t.string "disabled_reason"
    t.integer "max_pushes_per_week", default: 2, null: false
    t.datetime "notifications_disabled_at"
    t.datetime "permission_granted_at"
    t.datetime "permission_requested_at"
    t.datetime "prepermission_answered_at"
    t.boolean "push_enabled", default: false, null: false
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "workout_ready_enabled", default: false, null: false
    t.boolean "workout_reminders_enabled", default: false, null: false
    t.index ["user_id"], name: "index_user_notification_preferences_on_user_id", unique: true
  end

  create_table "user_segments", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "calculated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata_json", default: {}, null: false
    t.string "reason"
    t.string "segment_name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["calculated_at"], name: "index_user_segments_on_calculated_at"
    t.index ["segment_name", "active"], name: "index_user_segments_on_segment_name_and_active"
    t.index ["user_id", "segment_name"], name: "index_user_segments_on_user_id_and_segment_name", unique: true
    t.index ["user_id"], name: "index_user_segments_on_user_id"
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
    t.string "activation_platform"
    t.boolean "admin", default: false, null: false
    t.datetime "anonymized_at"
    t.boolean "community_enabled", default: false, null: false
    t.string "consent_source"
    t.datetime "created_at", null: false
    t.datetime "deletion_requested_at"
    t.string "email", default: "", null: false
    t.datetime "email_bounced_at"
    t.string "encrypted_password", default: "", null: false
    t.datetime "first_workout_completed_at"
    t.boolean "free_workout_used", default: false, null: false
    t.datetime "last_marketing_email_sent_at"
    t.boolean "marketing_consent", default: false, null: false
    t.string "name", default: "", null: false
    t.string "onboarding_flow"
    t.datetime "privacy_policy_accepted_at"
    t.string "privacy_policy_version"
    t.string "profile_visibility", default: "private", null: false
    t.string "provider"
    t.string "referral_code"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "reset_password_token_digest"
    t.datetime "terms_accepted_at"
    t.string "terms_version"
    t.boolean "test_account", default: false, null: false
    t.string "time_zone"
    t.datetime "trial_ends_at"
    t.datetime "trial_started_at"
    t.string "uid"
    t.datetime "unsubscribed_at"
    t.datetime "updated_at", null: false
    t.index ["account_type"], name: "index_users_on_account_type"
    t.index ["activation_platform"], name: "index_users_on_activation_platform"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_bounced_at"], name: "index_users_on_email_bounced_at"
    t.index ["marketing_consent"], name: "index_users_on_marketing_consent"
    t.index ["onboarding_flow"], name: "index_users_on_onboarding_flow"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["referral_code"], name: "index_users_on_referral_code", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["test_account"], name: "index_users_on_test_account"
    t.index ["trial_ends_at"], name: "index_users_on_trial_ends_at"
    t.index ["unsubscribed_at"], name: "index_users_on_unsubscribed_at"
  end

  create_table "workout_blocks", force: :cascade do |t|
    t.string "block_type", default: "single", null: false
    t.datetime "created_at", null: false
    t.string "label"
    t.integer "position", null: false
    t.integer "rest_between_rounds_seconds"
    t.integer "rounds", default: 1, null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_day_id", null: false
    t.index ["workout_day_id", "position"], name: "index_workout_blocks_on_workout_day_id_and_position"
    t.index ["workout_day_id"], name: "index_workout_blocks_on_workout_day_id"
  end

  create_table "workout_day_exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_minutes"
    t.bigint "exercise_id", null: false
    t.string "intensity"
    t.boolean "is_optional", default: false, null: false
    t.text "notes"
    t.integer "order_index"
    t.decimal "planned_weight", precision: 6, scale: 2
    t.integer "position_in_block"
    t.integer "reps"
    t.integer "rest_seconds"
    t.integer "rir"
    t.decimal "rpe", precision: 3, scale: 1
    t.integer "sets"
    t.bigint "substitution_group_id"
    t.integer "target_duration_seconds"
    t.integer "target_reps_max"
    t.integer "target_reps_min"
    t.string "tempo"
    t.datetime "updated_at", null: false
    t.bigint "workout_block_id", null: false
    t.bigint "workout_day_id", null: false
    t.index ["exercise_id"], name: "index_workout_day_exercises_on_exercise_id"
    t.index ["workout_block_id"], name: "index_workout_day_exercises_on_workout_block_id"
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
    t.integer "completed_sets_count"
    t.decimal "completion_rate", precision: 5, scale: 2
    t.string "completion_status", default: "completed", null: false
    t.datetime "created_at", null: false
    t.integer "duration_minutes"
    t.jsonb "exercise_logs", default: [], null: false
    t.jsonb "extra_block_data", default: {}
    t.string "extra_block_type"
    t.datetime "extra_completed_at"
    t.datetime "extra_started_at"
    t.integer "fatigue_level"
    t.text "notes"
    t.integer "planned_sets_count"
    t.jsonb "skipped_exercises", default: []
    t.string "source"
    t.string "status", default: "completed", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_day_id"
    t.index ["completion_status"], name: "index_workout_sessions_on_completion_status"
    t.index ["status"], name: "index_workout_sessions_on_status"
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
  add_foreign_key "ai_workout_chat_conversations", "users"
  add_foreign_key "analytics_experiment_assignments", "users"
  add_foreign_key "client_permissions", "personal_client_relationships"
  add_foreign_key "coach_insights", "fitness_profiles"
  add_foreign_key "coach_insights", "users"
  add_foreign_key "coach_recommendations", "exercises"
  add_foreign_key "coach_recommendations", "users"
  add_foreign_key "community_comments", "community_posts"
  add_foreign_key "community_comments", "users"
  add_foreign_key "community_posts", "users"
  add_foreign_key "community_reactions", "community_posts"
  add_foreign_key "community_reactions", "users"
  add_foreign_key "device_tokens", "users"
  add_foreign_key "equipment_identifications", "exercises"
  add_foreign_key "equipment_identifications", "users"
  add_foreign_key "exercise_sessions", "exercises"
  add_foreign_key "exercise_sessions", "workout_blocks"
  add_foreign_key "exercise_sessions", "workout_day_exercises"
  add_foreign_key "exercise_sessions", "workout_sessions"
  add_foreign_key "exercise_sets", "exercise_sessions"
  add_foreign_key "exercise_suggestion_logs", "users"
  add_foreign_key "exercises", "exercises", column: "regression_exercise_id"
  add_foreign_key "fitness_profiles", "users"
  add_foreign_key "health_data_points", "user_media", column: "user_media_id"
  add_foreign_key "health_data_points", "users"
  add_foreign_key "health_profiles", "users"
  add_foreign_key "mobile_auth_codes", "users"
  add_foreign_key "notification_deliveries", "device_tokens", column: "push_device_id"
  add_foreign_key "notification_deliveries", "users"
  add_foreign_key "onboarding_events", "users"
  add_foreign_key "personal_alerts", "users", column: "client_id"
  add_foreign_key "personal_alerts", "users", column: "personal_id"
  add_foreign_key "personal_client_relationships", "users", column: "client_id"
  add_foreign_key "personal_client_relationships", "users", column: "personal_id"
  add_foreign_key "personal_notes", "users", column: "client_id"
  add_foreign_key "personal_notes", "users", column: "personal_id"
  add_foreign_key "product_analytics_events", "users"
  add_foreign_key "public_profiles", "users"
  add_foreign_key "shared_workouts", "users", column: "owner_id"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "trainer_profiles", "users"
  add_foreign_key "user_badges", "users"
  add_foreign_key "user_events", "users"
  add_foreign_key "user_favorite_exercises", "exercises"
  add_foreign_key "user_favorite_exercises", "users"
  add_foreign_key "user_media", "users"
  add_foreign_key "user_notification_preferences", "users"
  add_foreign_key "user_segments", "users"
  add_foreign_key "user_training_preferences", "users"
  add_foreign_key "workout_blocks", "workout_days"
  add_foreign_key "workout_day_exercises", "exercises"
  add_foreign_key "workout_day_exercises", "workout_blocks"
  add_foreign_key "workout_day_exercises", "workout_days"
  add_foreign_key "workout_days", "workout_plans"
  add_foreign_key "workout_plans", "users"
  add_foreign_key "workout_sessions", "users"
  add_foreign_key "workout_sessions", "workout_days"
  add_foreign_key "workout_strategies", "fitness_profiles"
  add_foreign_key "workout_strategies", "users"
  add_foreign_key "workout_strategies", "workout_plans"
end

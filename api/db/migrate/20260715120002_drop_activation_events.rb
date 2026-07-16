class DropActivationEvents < ActiveRecord::Migration[8.1]
  # activation_events was an orphan table: no model, no reader, no writer in the
  # codebase (confirmed by audit). Its role is superseded by
  # product_analytics_events. Reversible: down recreates the exact schema.
  def up
    drop_table :activation_events, if_exists: true
  end

  def down
    create_table :activation_events, force: :cascade do |t|
      t.datetime :created_at, null: false
      t.string   :device
      t.string   :event_name, null: false
      t.bigint   :exercise_id
      t.string   :idempotency_key
      t.jsonb    :metadata, default: {}, null: false
      t.datetime :occurred_at, null: false
      t.string   :origin
      t.string   :platform
      t.string   :screen
      t.string   :session_id
      t.string   :subscription_status
      t.string   :trial_status
      t.datetime :updated_at, null: false
      t.bigint   :user_id
      t.bigint   :workout_day_id
      t.bigint   :workout_plan_id
      t.index [ :event_name, :occurred_at ], name: "index_activation_events_on_event_name_and_occurred_at"
      t.index [ :exercise_id ], name: "index_activation_events_on_exercise_id"
      t.index [ :session_id, :event_name, :idempotency_key ], name: "index_activation_events_on_session_event_idempotency", unique: true, where: "((idempotency_key IS NOT NULL) AND (session_id IS NOT NULL))"
      t.index [ :session_id, :event_name, :occurred_at ], name: "idx_on_session_id_event_name_occurred_at_ceb9d3841a"
      t.index [ :user_id, :event_name, :idempotency_key ], name: "index_activation_events_on_user_event_idempotency", unique: true, where: "((idempotency_key IS NOT NULL) AND (user_id IS NOT NULL))"
      t.index [ :user_id, :event_name, :occurred_at ], name: "idx_on_user_id_event_name_occurred_at_80fac2ebfc"
      t.index [ :user_id ], name: "index_activation_events_on_user_id"
      t.index [ :workout_day_id ], name: "index_activation_events_on_workout_day_id"
      t.index [ :workout_plan_id ], name: "index_activation_events_on_workout_plan_id"
    end
  end
end

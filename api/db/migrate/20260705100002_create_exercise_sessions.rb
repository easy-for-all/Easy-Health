class CreateExerciseSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :exercise_sessions do |t|
      t.references :workout_session, null: false, foreign_key: true
      t.references :workout_day_exercise, null: true, foreign_key: true
      t.references :exercise, null: false, foreign_key: true

      t.integer :order_index, null: false
      t.string :status, default: "in_progress", null: false
      t.string :exercise_kind, default: "strength", null: false

      t.integer :planned_sets
      t.integer :planned_reps
      t.decimal :planned_weight_kg, precision: 6, scale: 2
      t.integer :rest_seconds

      t.string :feeling
      t.integer :duration_minutes
      t.string :intensity
      t.integer :elapsed_seconds
      t.integer :target_seconds
      t.decimal :distance_km, precision: 6, scale: 2
      t.decimal :avg_speed_kmh, precision: 5, scale: 2
      t.string :avg_pace_per_km

      t.datetime :started_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :exercise_sessions, [:exercise_id, :status]
  end
end

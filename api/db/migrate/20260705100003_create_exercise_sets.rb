class CreateExerciseSets < ActiveRecord::Migration[8.1]
  def change
    create_table :exercise_sets do |t|
      t.references :exercise_session, null: false, foreign_key: true

      t.integer :set_number, null: false
      t.boolean :is_warmup, default: false, null: false
      t.decimal :weight_kg, precision: 6, scale: 2
      t.integer :reps
      t.datetime :completed_at, null: false

      t.timestamps
    end

    add_index :exercise_sets, [:exercise_session_id, :set_number],
      unique: true, name: "idx_exercise_sets_unique_set_number"
  end
end

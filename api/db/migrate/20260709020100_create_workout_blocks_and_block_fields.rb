class CreateWorkoutBlocksAndBlockFields < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_blocks do |t|
      t.references :workout_day, null: false, foreign_key: true

      t.string :block_type, null: false, default: "single"
      t.integer :position, null: false
      t.integer :rounds, null: false, default: 1
      t.integer :rest_between_rounds_seconds
      t.string :label

      t.timestamps
    end

    add_index :workout_blocks, [:workout_day_id, :position]

    add_reference :workout_day_exercises, :workout_block, null: true, foreign_key: true
    add_column :workout_day_exercises, :position_in_block, :integer
    add_column :workout_day_exercises, :target_reps_min, :integer
    add_column :workout_day_exercises, :target_reps_max, :integer
    add_column :workout_day_exercises, :target_duration_seconds, :integer
    add_column :workout_day_exercises, :tempo, :string
    add_column :workout_day_exercises, :rir, :integer
    add_column :workout_day_exercises, :rpe, :decimal, precision: 3, scale: 1
    add_column :workout_day_exercises, :is_optional, :boolean, default: false, null: false
    add_column :workout_day_exercises, :substitution_group_id, :bigint
    add_column :workout_day_exercises, :notes, :text
  end
end

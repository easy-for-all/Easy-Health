class EnsureWorkoutSessionCompletionFields < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:workout_sessions, :completion_status)
      add_column :workout_sessions, :completion_status, :string, default: "completed", null: false
    end
    unless column_exists?(:workout_sessions, :completion_rate)
      add_column :workout_sessions, :completion_rate, :decimal, precision: 5, scale: 2
    end
    unless column_exists?(:workout_sessions, :skipped_exercises)
      add_column :workout_sessions, :skipped_exercises, :jsonb, default: [], null: false
    end
    unless column_exists?(:workout_sessions, :completed_sets_count)
      add_column :workout_sessions, :completed_sets_count, :integer
    end
    unless column_exists?(:workout_sessions, :planned_sets_count)
      add_column :workout_sessions, :planned_sets_count, :integer
    end
    unless index_exists?(:workout_sessions, :completion_status)
      add_index :workout_sessions, :completion_status
    end

    unless column_exists?(:workout_sessions, :extra_block_type)
      add_column :workout_sessions, :extra_block_type, :string
    end
    unless column_exists?(:workout_sessions, :extra_block_data)
      add_column :workout_sessions, :extra_block_data, :jsonb, default: {}, null: false
    end
    unless column_exists?(:workout_sessions, :extra_started_at)
      add_column :workout_sessions, :extra_started_at, :datetime
    end
    unless column_exists?(:workout_sessions, :extra_completed_at)
      add_column :workout_sessions, :extra_completed_at, :datetime
    end
  end
end

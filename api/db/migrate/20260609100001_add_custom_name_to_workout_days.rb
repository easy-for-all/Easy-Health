class AddCustomNameToWorkoutDays < ActiveRecord::Migration[8.0]
  def change
    add_column :workout_days, :custom_name, :string
  end
end

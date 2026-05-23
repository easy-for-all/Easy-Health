class AddFreeWorkoutFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :free_workout_used, :boolean, default: false, null: false
    add_column :users, :first_workout_completed_at, :datetime
  end
end

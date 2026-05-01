class AddActivityPreferencesToHealthProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :health_profiles, :activity_preferences, :text, array: true, default: []
    add_column :health_profiles, :training_days_per_week, :integer, default: 3
  end
end

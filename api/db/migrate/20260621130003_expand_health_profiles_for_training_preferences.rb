class ExpandHealthProfilesForTrainingPreferences < ActiveRecord::Migration[8.0]
  def up
    add_column :health_profiles, :preferred_body_focus, :text, array: true, default: [], null: false
    add_column :health_profiles, :available_equipment, :text, array: true, default: [], null: false
    add_column :health_profiles, :avoided_exercise_ids, :bigint, array: true, default: [], null: false
    add_column :health_profiles, :session_duration_minutes, :integer
    add_column :health_profiles, :intensity_preference, :string
    add_column :health_profiles, :training_context, :string

    execute <<~SQL.squish
      UPDATE health_profiles
      SET training_location = CASE training_location
        WHEN 'gym' THEN 'full_gym'
        WHEN 'any' THEN 'unknown'
        ELSE training_location
      END
    SQL

    execute <<~SQL.squish
      UPDATE health_profiles
      SET preferred_training_styles = ARRAY[preferred_training_styles[1]]
      WHERE cardinality(preferred_training_styles) > 1
    SQL

    change_column_default :health_profiles, :training_location, from: "gym", to: "full_gym"
  end

  def down
    execute <<~SQL.squish
      UPDATE health_profiles
      SET training_location = CASE training_location
        WHEN 'full_gym' THEN 'gym'
        WHEN 'simple_gym' THEN 'gym'
        WHEN 'unknown' THEN 'any'
        WHEN 'condo' THEN 'home'
        WHEN 'hotel_travel' THEN 'home'
        ELSE training_location
      END
    SQL

    change_column_default :health_profiles, :training_location, from: "full_gym", to: "gym"
    remove_column :health_profiles, :training_context
    remove_column :health_profiles, :intensity_preference
    remove_column :health_profiles, :session_duration_minutes
    remove_column :health_profiles, :avoided_exercise_ids
    remove_column :health_profiles, :available_equipment
    remove_column :health_profiles, :preferred_body_focus
  end
end

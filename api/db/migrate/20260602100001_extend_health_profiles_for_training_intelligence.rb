class ExtendHealthProfilesForTrainingIntelligence < ActiveRecord::Migration[8.0]
  def change
    add_column :health_profiles, :limitations,               :text, array: true, default: []
    add_column :health_profiles, :preferred_training_styles, :text, array: true, default: []
    add_column :health_profiles, :adherence_score,           :decimal, precision: 5, scale: 2
    add_column :health_profiles, :last_profile_review_at,    :datetime
  end
end

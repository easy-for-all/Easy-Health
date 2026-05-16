class AddWizardFieldsToHealthProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :health_profiles, :modality,      :string, default: "ai_choice"
    add_column :health_profiles, :split_type,    :string, default: "ai_choice"
    add_column :health_profiles, :cardio_type,   :string
    add_column :health_profiles, :cardio_format, :string
    add_column :health_profiles, :custom_splits, :jsonb,  default: []
  end
end

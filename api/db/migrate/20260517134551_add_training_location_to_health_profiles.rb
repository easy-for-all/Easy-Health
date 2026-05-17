class AddTrainingLocationToHealthProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :health_profiles, :training_location, :string, default: "gym", null: false
  end
end

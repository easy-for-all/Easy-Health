class AddGenderToHealthProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :health_profiles, :gender, :string, if_not_exists: true
  end
end

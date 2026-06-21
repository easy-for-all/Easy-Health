class AddShowProgressPhotosToPublicProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :public_profiles, :show_progress_photos, :boolean, default: false, null: false
  end
end

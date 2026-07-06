class AddProfilingPromptsAnsweredToHealthProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :health_profiles, :profiling_prompts_answered, :jsonb, default: {}, null: false
  end
end

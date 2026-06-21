class CreateAiPromptVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_prompt_versions do |t|
      t.string  :name,         null: false
      t.string  :version,      null: false
      t.string  :prompt_type,  null: false
      t.text    :content,      null: false
      t.boolean :active,       null: false, default: false
      t.jsonb   :metadata,     null: false, default: {}
      t.timestamps
    end

    add_index :ai_prompt_versions, [:name, :version], unique: true
    add_index :ai_prompt_versions, :active
  end
end

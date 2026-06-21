class CreateUserEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :user_events do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :event_name, null: false
      t.jsonb :metadata, default: {}
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :user_events, [:user_id, :event_name]
    add_index :user_events, [:event_name, :created_at]
  end
end

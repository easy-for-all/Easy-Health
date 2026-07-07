class CreateOnboardingEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :onboarding_events do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :event_name, null: false
      t.string :onboarding_flow
      t.string :step_name
      t.jsonb :metadata, default: {}, null: false
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :onboarding_events, :event_name
    add_index :onboarding_events, :onboarding_flow
    add_index :onboarding_events, :step_name
    add_index :onboarding_events, :occurred_at
    add_index :onboarding_events, [:event_name, :occurred_at]
    add_index :onboarding_events, [:onboarding_flow, :event_name]
  end
end

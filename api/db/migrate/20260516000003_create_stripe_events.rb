class CreateStripeEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_events do |t|
      t.string   :stripe_event_id, null: false
      t.string   :event_type
      t.datetime :processed_at,    null: false

      t.timestamps
    end

    add_index :stripe_events, :stripe_event_id, unique: true
  end
end

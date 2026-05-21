class AddStatusToStripeEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :stripe_events, :status, :string, default: "processed", null: false
    add_column :stripe_events, :error_message, :text
  end
end

class AddProviderCostToAiUsageLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_usage_logs, :provider, :string, default: "anthropic", null: false
    add_column :ai_usage_logs, :estimated_cost_cents, :integer
    add_index  :ai_usage_logs, [:user_id, :provider, :created_at], name: "index_ai_usage_logs_on_user_provider_created"
  end
end

class AddOnboardingFlowToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :onboarding_flow, :string
    add_index :users, :onboarding_flow
  end
end

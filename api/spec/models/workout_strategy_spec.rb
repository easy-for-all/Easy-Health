require "rails_helper"

RSpec.describe WorkoutStrategy, type: :model do
  it "belongs to the plan and allows an optional fitness profile snapshot" do
    user = create(:user)
    plan = user.workout_plans.create!(active: true)

    strategy = described_class.create!(
      user: user,
      workout_plan: plan,
      strategy: { "strategy_version" => "v1", "training_split" => "full_body" }
    )

    expect(strategy.workout_plan).to eq(plan)
    expect(plan.workout_strategy).to eq(strategy)
  end
end

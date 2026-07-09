require "rails_helper"

RSpec.describe BlockUsageMetricsService do
  let(:user) { create(:user) }

  def exercise(name)
    Exercise.create!(
      name: name, exercise_type: "musculacao", muscle_group: "back",
      gif_url: "/exercise-images/gifdotreino/test/#{name.parameterize}.gif"
    )
  end

  def build_plan_with_block(block_type:, exercise_count: 2, owner: user)
    plan = owner.workout_plans.create!(active: true)
    day = plan.workout_days.create!(day_of_week: 1, name: "Treino A")
    block = day.workout_blocks.create!(block_type: block_type, position: 0, rounds: 3)
    exercise_count.times do |i|
      day.workout_day_exercises.create!(
        exercise: exercise("#{block_type} #{i}"), sets: 3, reps: 10, rest_seconds: 0,
        order_index: i, workout_block: block, position_in_block: i
      )
    end
    plan
  end

  describe "#call" do
    it "returns block_type_distribution counting real WorkoutBlock rows" do
      build_plan_with_block(block_type: "superset")
      build_plan_with_block(block_type: "superset", owner: create(:user))
      build_plan_with_block(block_type: "circuit", exercise_count: 3, owner: create(:user))

      result = described_class.new.call

      expect(result[:block_type_distribution]["superset"]).to eq(2)
      expect(result[:block_type_distribution]["circuit"]).to eq(1)
    end

    it "computes plans_with_composite_blocks_pct against active plans only" do
      build_plan_with_block(block_type: "superset")
      inactive_plan = user.workout_plans.create!(active: false)
      inactive_plan.workout_days.create!(day_of_week: 2, name: "Treino B")
      # 1 active plan with a composite block out of 1 active plan total (the inactive one doesn't count)
      result = described_class.new.call

      expect(result[:plans_with_composite_blocks_pct]).to eq(100.0)
    end

    it "returns 0.0 for plans_with_composite_blocks_pct when there are no active plans" do
      result = described_class.new.call
      expect(result[:plans_with_composite_blocks_pct]).to eq(0.0)
    end

    it "counts distinct users who have a completed/cancelled session logging a composite block exercise" do
      build_plan_with_block(block_type: "superset")
      other_user = create(:user)

      user.workout_sessions.create!(
        status: "completed", completed_at: Time.current, duration_minutes: 30,
        exercise_logs: [ { "exercise_id" => 1, "block_type" => "superset", "block_id" => 1 } ]
      )
      other_user.workout_sessions.create!(
        status: "completed", completed_at: Time.current, duration_minutes: 30,
        exercise_logs: [ { "exercise_id" => 2, "block_type" => "single", "block_id" => nil } ]
      )

      result = described_class.new.call

      expect(result[:users_who_trained_composite_block]).to eq(1)
    end

    it "computes completion_rate_by_block_type from distinct sessions per status" do
      user.workout_sessions.create!(
        status: "completed", completed_at: Time.current, duration_minutes: 30,
        exercise_logs: [
          { "exercise_id" => 1, "block_type" => "superset", "block_id" => 1 },
          { "exercise_id" => 2, "block_type" => "superset", "block_id" => 1 }
        ]
      )
      user.workout_sessions.create!(
        status: "cancelled", completion_status: "abandoned", duration_minutes: 10,
        exercise_logs: [ { "exercise_id" => 3, "block_type" => "superset", "block_id" => 2 } ]
      )

      result = described_class.new.call

      # 1 completed session + 1 cancelled session mentioning "superset" => 50%
      expect(result[:completion_rate_by_block_type]["superset"]).to eq(50.0)
    end
  end
end

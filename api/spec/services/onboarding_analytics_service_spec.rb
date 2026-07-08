require "rails_helper"

RSpec.describe OnboardingAnalyticsService do
  describe "with an empty database" do
    it "returns a well-formed structure with no data, without raising" do
      result = nil
      expect { result = described_class.new.call }.not_to raise_error

      expect(result[:flow_selection][:total]).to eq(0)
      expect(result[:conversion_by_flow]["quick"][:selected]).to eq(0)
      expect(result[:time_to_first_plan]["quick"][:count]).to eq(0)
      expect(result[:step_dropoff]["quick"]).to be_an(Array)
      expect(result[:first_workout_24h][:overall][:signup_to_first_workout_24h]).to eq(0)
      expect(result[:progressive_profiling][:summary][:shown]).to eq(0)
      expect(result[:ai_quality]["photo_ai"][:summaries_generated]).to eq(0)
      expect(result[:declared_preferences][:goals]).to eq([])
      expect(result[:activation_funnel][:steps]).to be_an(Array)
      expect(result[:activation_funnel][:steps].first[:count]).to eq(0)
    end
  end

  describe "flow_selection" do
    it "counts distinct users per flow with percentage" do
      quick_user = create(:user)
      complete_user = create(:user)
      OnboardingEventTracker.track(user: quick_user, event_name: "onboarding_flow_selected", onboarding_flow: "quick")
      OnboardingEventTracker.track(user: complete_user, event_name: "onboarding_flow_selected", onboarding_flow: "complete")

      result = described_class.new.call[:flow_selection]

      expect(result[:total]).to eq(2)
      expect(result[:by_flow]["quick"][:count]).to eq(1)
      expect(result[:by_flow]["quick"][:pct]).to eq(50.0)
    end
  end

  describe "conversion_by_flow" do
    it "computes conversion funnel per flow based on users.onboarding_flow" do
      user = create(:user, onboarding_flow: "quick")
      plan = WorkoutPlan.create!(user: user, active: true)
      WorkoutSession.create!(user: user, status: "completed", completion_status: "completed",
                              completed_at: Time.current, duration_minutes: 30)

      row = described_class.new.call[:conversion_by_flow]["quick"]

      expect(row[:selected]).to eq(1)
      expect(row[:created_workout]).to eq(1)
      expect(row[:executed_first]).to eq(1)
      expect(row[:conversion_to_workout_pct]).to eq(100.0)
    end
  end

  describe "time_to_first_plan" do
    it "computes the duration between flow selection and plan creation" do
      user = create(:user)
      OnboardingEventTracker.track(user: user, event_name: "onboarding_flow_selected", onboarding_flow: "quick",
                                    occurred_at: 30.seconds.ago)
      OnboardingEventTracker.track(user: user, event_name: "plan_created", onboarding_flow: "quick",
                                    occurred_at: Time.current)

      result = described_class.new.call[:time_to_first_plan]["quick"]

      expect(result[:count]).to eq(1)
      expect(result[:avg_seconds]).to be_within(2).of(30)
    end
  end

  describe "progressive_profiling" do
    it "aggregates shown/answered/skipped per question_key" do
      user = create(:user)
      OnboardingEventTracker.track(user: user, event_name: "progressive_question_shown", step_name: "available_equipment")
      OnboardingEventTracker.track(user: user, event_name: "progressive_question_answered", step_name: "available_equipment",
                                    metadata: { answer_value: "dumbbell" })

      result = described_class.new.call[:progressive_profiling]
      question = result[:by_question].find { |q| q[:question_key] == "available_equipment" }

      expect(question[:shown]).to eq(1)
      expect(question[:answered]).to eq(1)
      expect(question[:top_answer]).to eq("dumbbell")
    end
  end

  describe "declared_preferences" do
    it "buckets goals, locations and limitations from HealthProfile" do
      user = create(:user)
      create(:health_profile, user: user, goal: "lose_weight", training_location: "home", limitations: ["dor no joelho"])

      result = described_class.new.call[:declared_preferences]

      expect(result[:goals].first).to include(key: "lose_weight", count: 1)
      expect(result[:locations].first).to include(key: "home", count: 1)
      expect(result[:limitations].first).to include(label: "Joelho", count: 1)
    end
  end

  describe "activation_funnel" do
    it "computes arrived/completed percentages across the activation funnel steps" do
      user_a = create(:user, onboarding_flow: "quick")
      user_b = create(:user, onboarding_flow: "quick")
      user_c = create(:user, onboarding_flow: "quick")

      [user_a, user_b, user_c].each { |u| OnboardingEventTracker.track(user: u, event_name: "plan_created", onboarding_flow: "quick") }

      [user_b, user_c].each do |u|
        OnboardingEventTracker.track(user: u, event_name: "activation_ready_screen_viewed", onboarding_flow: "quick")
        OnboardingEventTracker.track(user: u, event_name: "activation_preview_viewed", onboarding_flow: "quick")
      end

      OnboardingEventTracker.track(user: user_c, event_name: "activation_exercise_details_opened", onboarding_flow: "quick")
      OnboardingEventTracker.track(user: user_c, event_name: "activation_start_clicked", onboarding_flow: "quick")
      OnboardingEventTracker.track(user: user_c, event_name: "workout_started", onboarding_flow: "quick", metadata: { is_first_workout: true })
      OnboardingEventTracker.track(user: user_c, event_name: "first_exercise_started", onboarding_flow: "quick")
      OnboardingEventTracker.track(user: user_c, event_name: "first_exercise_completed", onboarding_flow: "quick")
      OnboardingEventTracker.track(user: user_c, event_name: "workout_completed", onboarding_flow: "quick", metadata: { is_first_workout: true })

      steps = described_class.new.call[:activation_funnel][:steps]
      by_name = steps.index_by { |s| s[:step_name] }

      expect(by_name["plan_created"][:count]).to eq(3)
      expect(by_name["activation_ready_screen_viewed"][:count]).to eq(2)
      expect(by_name["activation_exercise_details_opened"][:count]).to eq(1)
      expect(by_name["activation_exercise_details_opened"][:pct_of_previous]).to eq(50.0)
      expect(by_name["activation_exercise_details_opened"][:pct_of_start]).to be_within(0.1).of(33.3)
      expect(by_name["first_workout_started"][:count]).to eq(1)
      expect(by_name["first_workout_completed"][:count]).to eq(1)
    end

    it "breaks down by onboarding_flow" do
      quick_user = create(:user, onboarding_flow: "quick")
      complete_user = create(:user, onboarding_flow: "complete")
      OnboardingEventTracker.track(user: quick_user, event_name: "plan_created", onboarding_flow: "quick")
      OnboardingEventTracker.track(user: complete_user, event_name: "plan_created", onboarding_flow: "complete")

      by_flow = described_class.new.call[:activation_funnel][:by_flow]

      expect(by_flow["quick"][:steps].find { |s| s[:step_name] == "plan_created" }[:count]).to eq(1)
      expect(by_flow["complete"][:steps].find { |s| s[:step_name] == "plan_created" }[:count]).to eq(1)
    end
  end

  describe "filters" do
    it "restricts flow-scoped views to the given onboarding_flow" do
      user = create(:user)
      OnboardingEventTracker.track(user: user, event_name: "onboarding_flow_selected", onboarding_flow: "complete")

      result = described_class.new(flow: "complete").call[:flow_selection]

      expect(result[:by_flow].keys).to eq(["complete"])
    end
  end
end

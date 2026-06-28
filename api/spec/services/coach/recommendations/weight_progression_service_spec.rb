require "rails_helper"

RSpec.describe Coach::Recommendations::WeightProgressionService do
  let(:user) { create(:user) }
  let!(:exercise) do
    Exercise.create!(
      name:           "Supino Reto",
      muscle_group:   "chest",
      exercise_type:  "musculacao",
      equipment_type: "barbell",
      difficulty:     "intermediate"
    )
  end

  let!(:plan) { WorkoutPlan.create!(user: user, active: true) }
  let!(:day)  { WorkoutDay.create!(workout_plan: plan, name: "A", day_of_week: 1, position: 0) }
  let!(:wde)  { WorkoutDayExercise.create!(workout_day: day, exercise: exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: 0) }

  def build_log(weight:, reps: [10, 10, 10], planned_sets: 3)
    {
      "exercise_id"  => exercise.id,
      "name"         => exercise.name,
      "exercise_type"=> "musculacao",
      "weight_by_set"=> Array.new(reps.size, weight),
      "reps"         => reps,
      "planned_sets" => planned_sets
    }
  end

  def create_session(log:, fatigue_level: 2, completion_status: "completed", days_ago: 3)
    user.workout_sessions.create!(
      completed_at:      days_ago.days.ago,
      duration_minutes:  45,
      fatigue_level:     fatigue_level,
      completion_status: completion_status,
      exercise_logs:     [ log ]
    )
  end

  subject(:service) { described_class.new(user: user) }

  describe "#call" do
    context "with sufficient consistent history" do
      before do
        create_session(log: build_log(weight: 15.0), days_ago: 7)
        create_session(log: build_log(weight: 15.0), days_ago: 3)
      end

      it "creates a pending weight_progression recommendation" do
        expect { service.call }.to change(CoachRecommendation, :count).by(1)
        rec = CoachRecommendation.last
        expect(rec.recommendation_type).to eq("weight_progression")
        expect(rec.status).to eq("pending")
        expect(rec.exercise_id).to eq(exercise.id)
        expect(rec.current_value).to eq(15.0)
        expect(rec.recommended_value).to be > 15.0
      end

      it "sets confidence based on session count" do
        service.call
        expect(CoachRecommendation.last.confidence).to be_between(0.60, 1.0)
      end
    end

    context "without sufficient history" do
      it "does not create a recommendation with only one session" do
        create_session(log: build_log(weight: 15.0), days_ago: 3)
        expect { service.call }.not_to change(CoachRecommendation, :count)
      end

      it "does not create a recommendation with no sessions" do
        expect { service.call }.not_to change(CoachRecommendation, :count)
      end
    end

    context "when performance is inconsistent" do
      it "does not create a recommendation when reps dropped" do
        create_session(log: build_log(weight: 15.0, reps: [10, 10, 10]), days_ago: 7)
        create_session(log: build_log(weight: 15.0, reps: [8, 8, 8]),   days_ago: 3)
        expect { service.call }.not_to change(CoachRecommendation, :count)
      end

      it "does not create a recommendation on high fatigue" do
        create_session(log: build_log(weight: 15.0), days_ago: 7, fatigue_level: 2)
        create_session(log: build_log(weight: 15.0), days_ago: 3, fatigue_level: 5)
        expect { service.call }.not_to change(CoachRecommendation, :count)
      end
    end

    context "when pending recommendation already exists" do
      before do
        create_session(log: build_log(weight: 15.0), days_ago: 7)
        create_session(log: build_log(weight: 15.0), days_ago: 3)
        CoachRecommendation.create!(
          user:                user,
          exercise:            exercise,
          recommendation_type: "weight_progression",
          status:              "pending",
          title:               "Progressão sugerida",
          message:             "msg",
          exercise_name:       exercise.name,
          unit:                "kg"
        )
      end

      it "does not create a duplicate pending recommendation" do
        expect { service.call }.not_to change(CoachRecommendation, :count)
      end
    end

    context "when exercise has no weight logged" do
      before do
        log_no_weight = build_log(weight: 0.0)
        create_session(log: log_no_weight, days_ago: 7)
        create_session(log: log_no_weight, days_ago: 3)
      end

      it "does not create a recommendation" do
        expect { service.call }.not_to change(CoachRecommendation, :count)
      end
    end

    context "when no active workout plan exists" do
      before { plan.update!(active: false) }

      it "returns nil without creating recommendations" do
        expect { service.call }.not_to change(CoachRecommendation, :count)
      end
    end
  end
end

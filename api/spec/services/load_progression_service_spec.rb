require "rails_helper"

RSpec.describe LoadProgressionService do
  let(:user) { create(:user) }
  let(:exercise_id) { 42 }

  def build_log(weight:, reps:, planned_sets: 3, feeling: nil)
    {
      "exercise_id" => exercise_id,
      "name" => "Supino Reto",
      "weight_by_set" => Array.new(reps.size, weight),
      "reps" => reps,
      "planned_sets" => planned_sets,
      "feeling" => feeling
    }
  end

  def create_session(log:, fatigue_level: nil, completion_status: "completed", days_ago: 3)
    user.workout_sessions.create!(
      completed_at: days_ago.days.ago,
      duration_minutes: 45,
      fatigue_level: fatigue_level,
      completion_status: completion_status,
      exercise_logs: [ log ]
    )
  end

  describe "#call" do
    context "with insufficient data" do
      it "returns maintain when no sessions exist" do
        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:action]).to eq("maintain")
        expect(result[:current_weight]).to be_nil
      end

      it "returns maintain with only one session" do
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]))
        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:action]).to eq("maintain")
        expect(result[:current_weight]).to be_nil
      end
    end

    context "with 2+ consistent sessions" do
      it "suggests increase when reps and weight are stable" do
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]), days_ago: 7)
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]), days_ago: 3)

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:action]).to eq("increase")
        expect(result[:suggested_weight]).to be > 15.0
        expect(result[:current_weight]).to eq(15.0)
      end

      it "uses correct increment for weights under 10kg" do
        create_session(log: build_log(weight: 8.0, reps: [ 10, 10, 10 ]), days_ago: 7)
        create_session(log: build_log(weight: 8.0, reps: [ 10, 10, 10 ]), days_ago: 3)

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:suggested_weight]).to eq(8.5)
      end

      it "uses correct increment for weights between 10-30kg" do
        create_session(log: build_log(weight: 20.0, reps: [ 10, 10, 10 ]), days_ago: 7)
        create_session(log: build_log(weight: 20.0, reps: [ 10, 10, 10 ]), days_ago: 3)

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:suggested_weight]).to eq(21.25)
      end

      it "uses 2.5kg increment for weights over 30kg" do
        create_session(log: build_log(weight: 40.0, reps: [ 8, 8, 8 ]), days_ago: 7)
        create_session(log: build_log(weight: 40.0, reps: [ 8, 8, 8 ]), days_ago: 3)

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:suggested_weight]).to eq(42.5)
      end
    end

    context "with high fatigue" do
      it "maintains weight when fatigue is 4" do
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]), days_ago: 7)
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]), fatigue_level: 4, days_ago: 3)

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:action]).to eq("maintain")
        expect(result[:reason]).to include("Fadiga")
      end

      it "maintains weight when fatigue is 5" do
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]), days_ago: 7)
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]), fatigue_level: 5, days_ago: 3)

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:action]).to eq("maintain")
      end
    end

    context "with reps drop" do
      it "maintains weight when reps decreased" do
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]), days_ago: 7)
        create_session(log: build_log(weight: 15.0, reps: [ 8, 7, 6 ]), days_ago: 3)

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:action]).to eq("maintain")
        expect(result[:reason]).to include("repetições")
      end
    end

    context "with partial completion" do
      it "maintains weight when last workout was partial" do
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]), days_ago: 7)
        create_session(
          log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]),
          completion_status: "completed_partial",
          days_ago: 3
        )

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:action]).to eq("maintain")
        expect(result[:reason]).to include("parcial")
      end
    end

    context "with incomplete sets" do
      it "maintains weight when fewer sets completed than planned" do
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ], planned_sets: 4), days_ago: 7)
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 0 ], planned_sets: 4), days_ago: 3)

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:action]).to eq("maintain")
        expect(result[:reason]).to include("Séries incompletas")
      end
    end

    context "with long break" do
      it "suggests maintain with conservative note when break exceeds 10 days" do
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]), days_ago: 25)
        create_session(log: build_log(weight: 15.0, reps: [ 10, 10, 10 ]), days_ago: 12)

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:action]).to eq("maintain")
        expect(result[:reason]).to include("intervalo")
      end
    end

    context "when reps are equal but weight was lower before" do
      it "maintains when last weight is lower than previous" do
        create_session(log: build_log(weight: 20.0, reps: [ 10, 10, 10 ]), days_ago: 7)
        create_session(log: build_log(weight: 17.5, reps: [ 10, 10, 10 ]), days_ago: 3)

        result = described_class.new(user: user, exercise_id: exercise_id).call
        expect(result[:action]).to eq("maintain")
      end
    end
  end
end

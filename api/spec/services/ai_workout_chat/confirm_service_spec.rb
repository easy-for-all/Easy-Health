require "rails_helper"

RSpec.describe AiWorkoutChat::ConfirmService do
  let(:user) { create(:user) }
  let(:preview) do
    {
      training_method: "upper_lower",
      plan_name: "Plano Teste Chat IA",
      rationale: "Motivo qualquer.",
      week_structure: [
        { name: "Superior", muscle_groups: %w[chest back shoulders] },
        { name: "Inferior", muscle_groups: %w[legs core] }
      ],
      sets_reps: { sets: 3, reps: 10, rest_seconds: 90 },
      progression_strategy: "Progressão linear.",
      safety_notes: ["Aquecer antes de treinar"]
    }.as_json
  end

  before do
    create(:health_profile, user: user)
    %w[chest back shoulders legs core].each { |group| create_browseable_exercise("Seguro #{group}", group) }
  end

  describe "#call" do
    context "when the conversation has a ready preview" do
      let(:conversation) do
        AiWorkoutChatConversation.create!(
          user: user, status: "previewing",
          collected_profile: { "goal" => "gain_muscle", "fitness_level" => "intermediate", "training_days_per_week" => 2, "training_location" => "full_gym" },
          generated_preview: preview
        )
      end

      it "creates a real active workout plan and marks the conversation as confirmed" do
        result = described_class.new(conversation).call

        expect(result.success?).to be true
        expect(result.workout_plan_id).to be_present

        plan = WorkoutPlan.find(result.workout_plan_id)
        expect(plan.active).to be true
        expect(plan.workout_days.count).to eq(2)

        conversation.reload
        expect(conversation.status).to eq("confirmed")
        expect(conversation.workout_plan_id).to eq(plan.id)
      end

      it "writes the collected profile back into the user's health profile" do
        described_class.new(conversation).call

        expect(user.health_profile.reload.goal).to eq("gain_muscle")
        expect(user.health_profile.training_days_per_week).to eq(2)
      end

      it "is idempotent when called twice" do
        first  = described_class.new(conversation).call
        second = described_class.new(conversation.reload).call

        expect(second.success?).to be true
        expect(second.workout_plan_id).to eq(first.workout_plan_id)
        expect(WorkoutPlan.where(user: user).count).to eq(1)
      end
    end

    context "when the conversation has no preview yet" do
      let(:conversation) { AiWorkoutChatConversation.create!(user: user, status: "collecting", collected_profile: {}) }

      it "returns a failure result without creating a plan" do
        result = described_class.new(conversation).call

        expect(result.success?).to be false
        expect(result.error).to eq("no_preview_to_confirm")
        expect(WorkoutPlan.where(user: user)).to be_empty
      end
    end
  end

  def create_browseable_exercise(name, muscle_group)
    Exercise.create!(
      name: name,
      exercise_type: "musculacao",
      muscle_group: muscle_group,
      equipment_type: "bodyweight",
      difficulty_level: "beginner",
      home_compatible: true,
      gif_url: "/exercise-images/gifdotreino/test/#{name.parameterize}.gif"
    )
  end
end

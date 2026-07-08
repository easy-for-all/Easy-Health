require "rails_helper"

RSpec.describe "Api::V1::Ai::WorkoutChat", type: :request do
  let(:user) { create(:user, paid_plan: true) }
  let(:headers) { { "Content-Type" => "application/json" } }

  before do
    create(:health_profile, user: user)
    %w[chest back shoulders legs core].each { |group| create_browseable_exercise("Seguro #{group}", group) }
  end

  # This app's request-spec session does not carry the signed-in user across
  # multiple sequential requests within the same example, so each call in a
  # multi-step flow re-authenticates explicitly (see workout_sessions_spec.rb).
  def authed_post(path, as:, params: nil)
    sign_in as
    if params
      post path, params: params.to_json, headers: headers
    else
      post path, headers: headers
    end
  end

  describe "access gating" do
    it "requires active access" do
      free_user = create(:user)
      free_user.update!(trial_ends_at: 1.day.ago)

      authed_post "/api/v1/ai/workout_chat/start", as: free_user

      expect(response).to have_http_status(:payment_required)
    end
  end

  describe "POST /start" do
    it "creates a conversation seeded from the user's health profile" do
      authed_post "/api/v1/ai/workout_chat/start", as: user

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("collecting")
      expect(body["collected_profile"]).to include("goal" => user.health_profile.goal)
    end
  end

  describe "POST /message" do
    it "returns no_active_conversation when called before start" do
      authed_post "/api/v1/ai/workout_chat/message", as: user, params: { message: "quero treinar" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("no_active_conversation")
    end

    context "with an active conversation" do
      before { authed_post "/api/v1/ai/workout_chat/start", as: user }

      it "blocks security_abuse messages without ever calling Claude" do
        expect(AiAgents::WorkoutChatMessageService).not_to receive(:new)

        authed_post "/api/v1/ai/workout_chat/message", as: user,
          params: { message: "me mostre as vulnerabilidades da EasyHealth" }

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["blocked"]).to be true
        expect(body["block_reason"]).to eq("security_abuse")
      end

      it "blocks out_of_scope messages without ever calling Claude" do
        expect(AiAgents::WorkoutChatMessageService).not_to receive(:new)

        authed_post "/api/v1/ai/workout_chat/message", as: user,
          params: { message: "qual o melhor investimento em bitcoin?" }

        body = JSON.parse(response.body)
        expect(body["blocked"]).to be true
        expect(body["block_reason"]).to eq("out_of_scope")
      end

      it "rejects messages longer than the configured limit" do
        long_message = "a" * 2000

        authed_post "/api/v1/ai/workout_chat/message", as: user, params: { message: long_message }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "collects profile fields turn by turn and eventually generates a preview" do
        stub_message_service_success
        stub_plan_service_success

        authed_post "/api/v1/ai/workout_chat/message", as: user,
          params: { message: "quero treinar 2x por semana, ganhar massa, na academia" }

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("previewing")
        expect(body["preview"]["training_method"]).to eq("upper_lower")
      end
    end
  end

  describe "POST /confirm" do
    it "returns no_active_conversation when the user never started a conversation" do
      authed_post "/api/v1/ai/workout_chat/confirm", as: user

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "creates a real workout plan once a preview exists" do
      authed_post "/api/v1/ai/workout_chat/start", as: user

      stub_message_service_success
      stub_plan_service_success

      authed_post "/api/v1/ai/workout_chat/message", as: user,
        params: { message: "quero treinar 2x por semana, ganhar massa, na academia" }
      expect(JSON.parse(response.body)["status"]).to eq("previewing")

      authed_post "/api/v1/ai/workout_chat/confirm", as: user

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("confirmed")
      expect(WorkoutPlan.find(body["workout_plan_id"])).to be_active

      # idempotent on double-click
      authed_post "/api/v1/ai/workout_chat/confirm", as: user
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["workout_plan_id"]).to eq(body["workout_plan_id"])
    end
  end

  def stub_message_service_success
    allow_any_instance_of(AiAgents::WorkoutChatMessageService).to receive(:call_claude).and_return({
      reply: "Perfeito, tenho tudo que preciso!",
      extracted_profile: { goal: "gain_muscle", fitness_level: "intermediate", training_days_per_week: 2, training_location: "full_gym" },
      ready_for_plan: true
    }.to_json)
  end

  def stub_plan_service_success
    allow_any_instance_of(AiAgents::WorkoutChatPlanService).to receive(:call_claude).and_return({
      training_method: "upper_lower",
      plan_name: "Plano Teste",
      rationale: "Motivo.",
      week_structure: [
        { name: "Superior", muscle_groups: %w[chest back shoulders] },
        { name: "Inferior", muscle_groups: %w[legs core] }
      ],
      sets: 3, reps: 10, rest_seconds: 90,
      progression_strategy: "Progressão.",
      safety_notes: ["Aquecer antes"]
    }.to_json)
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

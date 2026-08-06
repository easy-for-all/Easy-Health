require "rails_helper"

RSpec.describe "Api::V1::Anonymous::WorkoutPlans", type: :request do
  let(:installation_id) { "anon-install-1" }
  let!(:installation) do
    AppInstallation.create!(installation_id: installation_id, platform: "android", native: true, app_build: "60")
  end
  let!(:session) do
    AnonymousOnboardingSession.create!(app_installation: installation, profile_answers: { "goal" => "gain_muscle" })
  end

  def token_for(id = installation_id, session_id = session.id)
    AnonymousSessions::Token.issue(session_id: session_id, installation_id: id)
  end

  def headers(token: token_for, installation: installation_id, platform: "android", build: "60")
    {
      "Authorization" => "Bearer #{token}",
      "X-Installation-Id" => installation,
      "X-Platform" => platform,
      "X-App-Build" => build
    }.compact
  end

  # O gerador de verdade chama a OpenAI. O que estes testes medem é o contrato do
  # endpoint — limite, posse, shape — não a qualidade do plano.
  def stub_generation!
    allow_any_instance_of(WorkoutPlanGeneratorService).to receive(:call) do |service|
      owner = service.instance_variable_get(:@owner)
      owner.plans.update_all(active: false)
      plan = WorkoutPlan.create!(active: true, **owner.plan_attributes)
      AiTrainingDecisionLog.create!(
        workout_plan: plan, generation_type: "workout_plan", status: "success", **owner.log_attributes
      )
      plan
    end
  end

  before { ENV["ANONYMOUS_GENERATION_ENABLED"] = "true" }
  after  { ENV.delete("ANONYMOUS_GENERATION_ENABLED") }

  describe "POST generate" do
    before { stub_generation! }

    it "generates a plan owned by the installation, with no user" do
      post "/api/v1/anonymous/workout_plan/generate", headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["plans_remaining"]).to eq(2)

      plan = WorkoutPlan.last
      expect(plan.user_id).to be_nil
      expect(plan.app_installation_id).to eq(installation.id)
    end

    it "refuses the fourth plan" do
      3.times { post "/api/v1/anonymous/workout_plan/generate", headers: headers, as: :json }
      expect(session.reload.plans_generated_count).to eq(3)

      post "/api/v1/anonymous/workout_plan/generate", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("anonymous_plan_limit_reached")
      expect(response.parsed_body["plans_remaining"]).to eq(0)
      expect(WorkoutPlan.owned_by_installation(installation).count).to eq(3)
    end

    # A regra que impede um loop de retry de virar geração ilimitada: a vaga é
    # reservada na TENTATIVA, antes de qualquer chamada ao provedor.
    it "spends a slot even when the generation blows up" do
      allow_any_instance_of(WorkoutPlanGeneratorService).to receive(:call).and_raise(StandardError, "provider down")

      post "/api/v1/anonymous/workout_plan/generate", headers: headers, as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(session.reload.plans_generated_count).to eq(1)
      expect(session.last_generation_status).to eq("failed")
    end

    it "is unavailable when the global circuit breaker is open" do
      ENV["ANONYMOUS_GENERATION_DAILY_GLOBAL_MAX"] = "0"

      post "/api/v1/anonymous/workout_plan/generate", headers: headers, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(session.reload.plans_generated_count).to eq(0)
    ensure
      ENV.delete("ANONYMOUS_GENERATION_DAILY_GLOBAL_MAX")
    end

    it "is disabled entirely without the kill-switch" do
      ENV["ANONYMOUS_GENERATION_ENABLED"] = "false"

      post "/api/v1/anonymous/workout_plan/generate", headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "authentication" do
    it "rejects a token issued for another installation" do
      other = AppInstallation.create!(installation_id: "anon-install-2", platform: "android", native: true, app_build: "60")
      other_session = AnonymousOnboardingSession.create!(app_installation: other)

      post "/api/v1/anonymous/workout_plan/generate",
           headers: headers(token: token_for("anon-install-2", other_session.id)), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["reason"]).to eq("installation_mismatch")
    end

    it "rejects an expired token" do
      stale = AnonymousSessions::Token.issue(
        session_id: session.id, installation_id: installation_id, now: 25.hours.ago
      )

      get "/api/v1/anonymous/state", headers: headers(token: stale)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["reason"]).to eq("expired_token")
    end

    it "rejects a garbage token" do
      get "/api/v1/anonymous/state", headers: headers(token: "eh_anon.not-a-real-token")

      expect(response).to have_http_status(:unauthorized)
    end

    # Web e PWA não participam do modo anônimo. Sem esta checagem, abrir o
    # backend para o Android abriria para o navegador junto.
    it "rejects a non-native platform" do
      get "/api/v1/anonymous/state", headers: headers(platform: "web")

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["reason"]).to eq("not_native")
    end

    it "rejects a build below the cut" do
      ENV["ANONYMOUS_MODE_MIN_BUILD"] = "70"

      get "/api/v1/anonymous/state", headers: headers(build: "60")

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["reason"]).to eq("build_too_old")
    ensure
      ENV.delete("ANONYMOUS_MODE_MIN_BUILD")
    end

    it "stops accepting the token once the session is claimed" do
      session.update!(claimed_at: Time.current, claimed_by_user: create(:user))

      get "/api/v1/anonymous/state", headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["reason"]).to eq("session_claimed")
    end
  end

  describe "scoping" do
    before { stub_generation! }

    # Um token anônimo válido não pode virar chave de leitura do plano alheio só
    # por passar outro id na URL.
    it "does not serve a day belonging to another owner" do
      other_plan = WorkoutPlan.create!(user: create(:user), active: true)
      other_day = other_plan.workout_days.create!(name: "Alheio", position: 1, day_of_week: 1)

      get "/api/v1/anonymous/workout_days/#{other_day.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "serves its own plan" do
      post "/api/v1/anonymous/workout_plan/generate", headers: headers, as: :json

      get "/api/v1/anonymous/workout_plan", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(WorkoutPlan.owned_by_installation(installation).first.id)
    end

    it "reports the state without a plan" do
      get "/api/v1/anonymous/state", headers: headers

      expect(response.parsed_body).to include(
        "plans_remaining" => 3, "has_active_plan" => false, "max_plans" => 3
      )
    end
  end
end

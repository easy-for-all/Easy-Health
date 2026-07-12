require "rails_helper"

RSpec.describe "Api::V1::AiAgents", type: :request do
  let(:user)    { create(:user, paid_plan: true) }
  let(:headers) { { "Content-Type" => "application/json" } }

  before { sign_in user }

  # The rate-limit check runs in a before_action, so a blocked request never
  # reaches the Anthropic call — no stubbing needed to assert the 429.
  def seed_usage(task_type, count)
    count.times do
      AiUsageLog.create!(user: user, task_type: task_type, model: "test-model", status: "success")
    end
  end

  describe "GET /api/v1/ai_agents/personal_trainer" do
    it "returns 429 once the daily limit is reached" do
      seed_usage("agent_personal_trainer", RateLimiter::DAILY_LIMITS["agent_personal_trainer"])

      get "/api/v1/ai_agents/personal_trainer", headers: headers

      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)["error"]).to include("limite diário")
    end

    it "does not count usage logged on a previous day" do
      seed_usage("agent_personal_trainer", RateLimiter::DAILY_LIMITS["agent_personal_trainer"])
      AiUsageLog.where(user: user).update_all(created_at: 1.day.ago)

      get "/api/v1/ai_agents/personal_trainer", headers: headers

      expect(response).not_to have_http_status(:too_many_requests)
    end
  end

  describe "GET /api/v1/ai_agents/conditioning" do
    it "returns 429 once the daily limit is reached" do
      seed_usage("agent_conditioning", RateLimiter::DAILY_LIMITS["agent_conditioning"])

      get "/api/v1/ai_agents/conditioning", headers: headers

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "admin bypass" do
    let(:user) { create(:user, :admin, paid_plan: true) }

    it "never rate-limits admins" do
      seed_usage("agent_personal_trainer", RateLimiter::DAILY_LIMITS["agent_personal_trainer"] + 5)

      get "/api/v1/ai_agents/personal_trainer", headers: headers

      expect(response).not_to have_http_status(:too_many_requests)
    end
  end
end

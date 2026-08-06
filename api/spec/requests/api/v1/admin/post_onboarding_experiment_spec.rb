require "rails_helper"

RSpec.describe "Api::V1::Admin::Analytics post_onboarding_experiment", type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:regular) { create(:user) }

  it "requires an admin" do
    sign_in regular
    get "/api/v1/admin/analytics/post_onboarding_experiment"

    expect(response).not_to have_http_status(:ok)
  end

  it "returns the panel for an admin" do
    sign_in admin
    get "/api/v1/admin/analytics/post_onboarding_experiment"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["experiment_key"]).to eq(Analytics::ExperimentRegistry::ANDROID_POST_ONBOARDING_GATE)
    expect(body["header"]).to be_present
    expect(body["funnels"].size).to eq(2)
    expect(body["guardrails"]).to have_key("events_missing_installation_id")
  end

  # Os filtros são validados DENTRO do serviço, então um valor inventado cai no
  # default em vez de virar erro ou, pior, de chegar cru a uma query.
  it "falls back to the defaults for unknown filter values" do
    sign_in admin
    get "/api/v1/admin/analytics/post_onboarding_experiment",
        params: { period: "last_century", audience: "everyone", variant: "third_arm" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["filters"]).to include(
      "period" => "since_start", "audience" => "external", "variant" => "all"
    )
  end

  # Um painel quebrado nunca vira 500: o admin precisa saber que a leitura
  # falhou, e o resto da página continua utilizável.
  it "answers 503 when the aggregation blows up" do
    sign_in admin
    allow(Analytics::PostOnboardingExperiment).to receive(:new).and_raise(StandardError, "boom")

    get "/api/v1/admin/analytics/post_onboarding_experiment"

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body["error"]).to be_present
  end
end

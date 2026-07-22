require "rails_helper"

RSpec.describe "Api::V1::Billing", type: :request do
  let(:user) { create(:user, paid_plan: true) }

  def stripe_env(overrides = {})
    {
      "STRIPE_SECRET_KEY" => "sk_test_checkout",
      "STRIPE_PRICE_PRO_MONTHLY" => "price_monthly_123",
      "STRIPE_PRICE_PRO_YEARLY" => "price_yearly_123",
      "FRONTEND_URL" => "https://easyhealth.art"
    }.merge(overrides)
  end

  def fake_checkout_session(id: "cs_test_123", url: "https://checkout.stripe.com/c/pay")
    double("Stripe::Checkout::Session", id: id, url: url)
  end

  before do
    user.subscription.update!(stripe_customer_id: "cus_existing123")
  end

  describe "POST /api/v1/billing/checkout" do
    it "creates a yearly checkout session and returns URL plus session id" do
      sign_in user
      session = fake_checkout_session(id: "cs_yearly")

      with_env(stripe_env) do
        expect(Stripe::Checkout::Session).to receive(:create).with(
          hash_including(
            customer: "cus_existing123",
            mode: "subscription",
            line_items: [hash_including(price: "price_yearly_123", quantity: 1)]
          )
        ).and_return(session)

        post "/api/v1/billing/checkout", params: { plan: "pro_yearly" }, as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "checkout_url" => "https://checkout.stripe.com/c/pay",
        "session_id" => "cs_yearly"
      )
    end

    it "creates a monthly checkout session" do
      sign_in user

      with_env(stripe_env) do
        expect(Stripe::Checkout::Session).to receive(:create).with(
          hash_including(line_items: [hash_including(price: "price_monthly_123")])
        ).and_return(fake_checkout_session(id: "cs_monthly"))

        post "/api/v1/billing/checkout", params: { plan: "pro_monthly" }, as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["session_id"]).to eq("cs_monthly")
    end

    it "returns a structured error for an invalid plan" do
      sign_in user

      with_env(stripe_env) do
        post "/api/v1/billing/checkout", params: { plan: "enterprise" }, as: :json
      end

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("billing_invalid_plan")
      expect(response.parsed_body.dig("error", "message")).to eq("Este plano não está disponível no momento.")
    end

    it "returns authentication_required for an unauthenticated user" do
      post "/api/v1/billing/checkout", params: { plan: "pro_yearly" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("authentication_required")
    end

    it "returns a safe configuration error when a price id is missing" do
      sign_in user

      with_env(stripe_env("STRIPE_PRICE_PRO_YEARLY" => nil)) do
        post "/api/v1/billing/checkout", params: { plan: "pro_yearly" }, as: :json
      end

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("billing_configuration_error")
      expect(response.body).not_to include("STRIPE_PRICE_PRO_YEARLY")
    end

    it "does not leak Stripe internals when checkout creation fails" do
      sign_in user

      with_env(stripe_env) do
        allow(Stripe::Checkout::Session).to receive(:create).and_raise(Stripe::StripeError.new("raw stripe failure"))

        post "/api/v1/billing/checkout", params: { plan: "pro_yearly" }, as: :json
      end

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body.dig("error", "code")).to eq("billing_checkout_creation_failed")
      expect(response.parsed_body.dig("error", "message")).to eq("Não foi possível iniciar o checkout.")
      expect(response.body).not_to include("raw stripe failure")
    end
  end

  describe "CORS" do
    it "allows preflight from the configured local origin" do
      options "/api/v1/billing/checkout", headers: {
        "Origin" => "http://localhost:3000",
        "Access-Control-Request-Method" => "POST",
        "Access-Control-Request-Headers" => "content-type"
      }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Access-Control-Allow-Origin"]).to eq("http://localhost:3000")
      expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
      expect(response.headers["Access-Control-Allow-Methods"]).to include("POST")
    end
  end
end

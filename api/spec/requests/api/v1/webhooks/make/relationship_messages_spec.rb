require "rails_helper"

RSpec.describe "POST /api/v1/webhooks/make/relationship-message", type: :request do
  let(:user)   { create(:user) }
  let(:secret) { "test-make-secret" }

  let(:valid_payload) do
    {
      user_id:         user.id.to_s,
      event_name:      "user_created",
      journey_key:     "onboarding",
      step_key:        "welcome_email",
      channel:         "email",
      provider:        "brevo",
      template_key:    "EH_001_WELCOME",
      subject:         "Bem-vindo",
      recipient_email: user.email,
      status:          "sent",
      sent_at:         Time.current.iso8601,
      metadata:        { make_execution_id: "exec-001", make_scenario: "easyhealth_v1" }
    }
  end

  let(:valid_headers) do
    { "X-Make-Secret" => secret, "CONTENT_TYPE" => "application/json" }
  end

  before do
    stub_const("ENV", ENV.to_h.merge("MAKE_INBOUND_WEBHOOK_SECRET" => secret))
  end

  def post_webhook(payload: valid_payload, headers: valid_headers)
    post "/api/v1/webhooks/make/relationship-message",
         params: payload.to_json,
         headers: headers
  end

  def json_body
    JSON.parse(response.body)
  end

  describe "authentication" do
    it "returns 401 when X-Make-Secret is missing" do
      post_webhook(headers: { "CONTENT_TYPE" => "application/json" })
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 when X-Make-Secret is wrong" do
      post_webhook(headers: valid_headers.merge("X-Make-Secret" => "wrong"))
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "successful registration" do
    it "returns 201 with id" do
      post_webhook
      expect(response).to have_http_status(:created)
      expect(json_body["status"]).to eq("ok")
      expect(json_body["id"]).to be_present
    end

    it "persists the relationship_message" do
      expect { post_webhook }.to change(RelationshipMessage, :count).by(1)
    end

    it "sets sent_at and status on the persisted record" do
      post_webhook
      message = RelationshipMessage.last
      expect(message.sent_at).to be_present
      expect(message.status).to eq("sent")
    end
  end

  describe "idempotency" do
    it "does not create a duplicate on second call with same execution_id" do
      post_webhook
      expect { post_webhook }.not_to change(RelationshipMessage, :count)
    end

    it "returns 201 on both calls" do
      post_webhook
      post_webhook
      expect(response).to have_http_status(:created)
    end
  end

  describe "failed status" do
    let(:failed_payload) do
      valid_payload.merge(
        status: "failed",
        sent_at: nil,
        error_message: "Brevo API error",
        metadata: { make_execution_id: "exec-002" }
      )
    end

    it "stores failed_at and error_message" do
      post_webhook(payload: failed_payload)
      message = RelationshipMessage.last
      expect(message.status).to eq("failed")
      expect(message.failed_at).to be_present
      expect(message.error_message).to eq("Brevo API error")
    end
  end

  describe "user not found" do
    it "returns 404" do
      post_webhook(payload: valid_payload.merge(user_id: "999999"))
      expect(response).to have_http_status(:not_found)
      expect(json_body["error"]).to eq("user_not_found")
    end
  end

  describe "invalid payload" do
    it "returns 422 for invalid status" do
      post_webhook(payload: valid_payload.merge(status: "bogus"))
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 for invalid channel" do
      post_webhook(payload: valid_payload.merge(channel: "fax"))
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

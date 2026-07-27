require "rails_helper"

RSpec.describe "Api::V1::Integrations::Make::EventDeliveryCallbacks", type: :request do
  let(:token) { "callback-secret" }
  let(:user) { create(:user) }
  let(:delivery) do
    UserEvent.create!(
      user: user,
      event_name: "first_workout_completed",
      occurred_at: Time.current,
      source: "spec",
      idempotency_key: "first_workout_completed:#{user.id}:callback",
      make_delivery_status: "accepted_by_make",
      make_processing_status: "unknown",
      metadata: { "safe" => "yes" },
      payload_json: { event_name: "first_workout_completed" }
    )
  end

  let(:path) { "/api/v1/integrations/make/event_delivery_callbacks" }

  around do |example|
    with_env("MAKE_DELIVERY_CALLBACK_TOKEN" => token) { example.run }
  end

  def headers(auth_token = token)
    { "Authorization" => "Bearer #{auth_token}", "CONTENT_TYPE" => "application/json" }
  end

  def payload(overrides = {})
    {
      event_id: delivery.id.to_s,
      idempotency_key: delivery.idempotency_key,
      event_name: delivery.event_name,
      status: "routed",
      scenario: "first-workout-completed-push",
      execution_id: "make-exec-1",
      occurred_at: Time.current.iso8601,
      message: "Evento encaminhado"
    }.merge(overrides)
  end

  it "returns 401 with an invalid token" do
    post path, params: payload.to_json, headers: headers("wrong")
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 422 for an invalid status" do
    post path, params: payload(status: "bogus").to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "updates the internal Make status with a valid token" do
    post path, params: payload.to_json, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("success" => true)
    expect(delivery.reload.make_processing_status).to eq("routed")
    expect(delivery.make_processing_message).to eq("Evento encaminhado")
    expect(delivery.make_execution_id).to eq("make-exec-1")
    expect(delivery.make_callback_at).to be_present
    expect(delivery.metadata.dig("last_make_callback", "scenario")).to eq("first-workout-completed-push")
  end

  it "is idempotent for duplicate callbacks" do
    post path, params: payload(status: "completed").to_json, headers: headers
    expect(delivery.reload.make_callback_at).to be_present

    expect do
      post path, params: payload(status: "completed").to_json, headers: headers
    end.not_to change(UserEvent, :count)

    expect(response).to have_http_status(:ok)
    expect(delivery.reload.make_processing_status).to eq("completed")
    expect(delivery.make_callback_at).to be_present
  end

  it "returns 404 for an unknown delivery" do
    post path,
         params: payload(event_id: "999999", idempotency_key: "missing").to_json,
         headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it "can locate the delivery by event_id when idempotency_key is absent" do
    post path, params: payload(idempotency_key: nil, status: "filtered").to_json, headers: headers

    expect(response).to have_http_status(:ok)
    expect(delivery.reload.make_processing_status).to eq("filtered")
  end
end

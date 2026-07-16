require "rails_helper"

RSpec.describe "Api::V1::Admin#push_test", type: :request do
  let(:admin) { create(:user, :admin) }

  def sent_result
    FirebasePushService::Result.new(status: "sent", message_id: "projects/x/messages/1", invalid_token: false)
  end

  def stub_fcm_sent
    allow(FirebasePushService).to receive(:configured?).and_return(true)
    allow_any_instance_of(FirebasePushService).to receive(:deliver).and_return(sent_result)
  end

  describe "authorization" do
    it "is forbidden for a non-admin user" do
      sign_in create(:user)
      post "/api/v1/admin/push_test"
      expect(response).to have_http_status(:forbidden)
    end

    it "does not send when unauthenticated" do
      expect { post "/api/v1/admin/push_test" }
        .not_to change { UserEvent.where(event_name: "admin_push_test_requested").count }
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "as admin" do
    before { sign_in admin }

    it "sends to the admin's own active token and returns masked results (no raw token)" do
      stub_fcm_sent
      token = admin.device_tokens.create!(token: "real-secret-token-value", platform: "android")

      post "/api/v1/admin/push_test"

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["ok"]).to be(true)
      expect(json["correlation_id"]).to be_present
      device = json["devices"].first
      expect(device["status"]).to eq("sent")
      expect(device["masked_token"]).to eq(token.masked_token)
      # The raw token must never appear anywhere in the response body.
      expect(response.body).not_to include("real-secret-token-value")
    end

    it "records an audit event for the admin" do
      stub_fcm_sent
      admin.device_tokens.create!(token: "tok-audit", platform: "android")

      expect { post "/api/v1/admin/push_test" }
        .to change { UserEvent.where(user_id: admin.id, event_name: "admin_push_test_requested").count }.by(1)
    end

    it "NEVER targets a user_id supplied in params — only the current admin" do
      stub_fcm_sent
      other = create(:user)
      other_token = other.device_tokens.create!(token: "other-user-token", platform: "android")
      admin.device_tokens.create!(token: "admin-token", platform: "android")

      post "/api/v1/admin/push_test", params: { user_id: other.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(other_token.masked_token)
      expect(UserEvent.where(user_id: other.id, event_name: "admin_push_test_requested")).to be_empty
    end

    it "returns 422 when the admin has no active device token" do
      allow(FirebasePushService).to receive(:configured?).and_return(true)
      post "/api/v1/admin/push_test"
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("no_active_device")
    end

    it "maps a rate-limited result to HTTP 429" do
      rate_limited = AdminPushTestService::Result.new(ok: false, error: "rate_limited", correlation_id: "c", devices: [])
      allow_any_instance_of(AdminPushTestService).to receive(:call).and_return(rate_limited)

      post "/api/v1/admin/push_test"
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body["error"]).to eq("rate_limited")
    end
  end
end

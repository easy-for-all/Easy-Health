require "rails_helper"

RSpec.describe "Api::V1::DeviceTokens", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  describe "POST /api/v1/device_tokens" do
    it "registers a token for the current user" do
      post "/api/v1/device_tokens", params: { token: "abc123", platform: "android", permission_status: "granted" }
      expect(response).to have_http_status(:ok)
      expect(user.device_tokens.active.pluck(:token)).to include("abc123")
    end

    it "re-enables a previously invalidated token on re-registration" do
      token = user.device_tokens.create!(token: "abc123", platform: "android")
      token.invalidate!("test")

      post "/api/v1/device_tokens", params: { token: "abc123", platform: "android" }
      expect(token.reload.invalidated_at).to be_nil
      expect(token.enabled).to be(true)
    end

    it "does not create notification preferences or enable push for a granted token" do
      post "/api/v1/device_tokens", params: { token: "abc123", platform: "android", permission_status: "granted" }

      expect(response).to have_http_status(:ok)
      # Native permission grant is NOT product consent — prefs stay absent until
      # the explicit EasyHealth consent flow runs.
      expect(user.notification_preferences).to be_nil
    end

    it "re-attaches a token previously owned by another user (unique index, single row)" do
      other = create(:user)
      shared = other.device_tokens.create!(token: "shared-device", platform: "android")

      post "/api/v1/device_tokens", params: { token: "shared-device", platform: "android" }

      expect(response).to have_http_status(:ok)
      expect(DeviceToken.where(token: "shared-device").count).to eq(1)
      expect(shared.reload.user_id).to eq(user.id)
      expect(other.device_tokens.active).to be_empty
    end
  end

  describe "PATCH/DELETE ownership" do
    it "cannot update another user's device" do
      other = create(:user).device_tokens.create!(token: "other", platform: "android")
      patch "/api/v1/device_tokens/#{other.id}", params: { app_version: "9.9" }
      expect(response).to have_http_status(:not_found)
      expect(other.reload.app_version).to be_nil
    end

    it "logically disables (does not destroy) on DELETE" do
      token = user.device_tokens.create!(token: "abc123", platform: "android")
      delete "/api/v1/device_tokens/#{token.id}"
      expect(response).to have_http_status(:no_content)
      expect(token.reload.enabled).to be(false)
      expect(DeviceToken.exists?(token.id)).to be(true)
    end
  end
end

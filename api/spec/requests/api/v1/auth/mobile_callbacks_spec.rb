require "rails_helper"

RSpec.describe "Api::V1::Auth::MobileCallbacks", type: :request do
  let(:user) { create(:user) }

  describe "POST /api/v1/auth/mobile/exchange" do
    it "exchanges a valid code for an authenticated session" do
      code = MobileAuthCode.issue_for!(user: user, platform: "android")

      post "/api/v1/auth/mobile/exchange", params: { code: code, platform: "android" }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(user.id)
      expect(body["email"]).to eq(user.email)
      expect(MobileAuthCode.last.used_at).to be_present

      get "/api/v1/auth/me"
      expect(response).to have_http_status(:ok)
    end

    it "rejects an expired code" do
      create(:mobile_auth_code, user: user, code: "expired", expires_at: 1.minute.ago)

      post "/api/v1/auth/mobile/exchange", params: { code: "expired", platform: "android" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Código expirado")
    end

    it "rejects a used code" do
      create(:mobile_auth_code, user: user, code: "used", used_at: Time.current)

      post "/api/v1/auth/mobile/exchange", params: { code: "used", platform: "android" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Código já utilizado")
    end

    it "rejects an unsupported platform" do
      post "/api/v1/auth/mobile/exchange", params: { code: "anything", platform: "desktop" }, as: :json

      expect(response.status).to eq(422)
      expect(response.parsed_body["error"]).to eq("Plataforma inválida")
    end
  end
end

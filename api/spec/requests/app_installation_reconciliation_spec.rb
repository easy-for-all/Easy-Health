require "rails_helper"

# Marco 1/3: every authenticated request carrying X-Installation-Id re-links the
# installation to the signed-in user, so a missed register no longer leaves the
# installation anonymous forever.
RSpec.describe "AppInstallation reconciliation", type: :request do
  let(:user) { create(:user) }
  let(:header) { { "X-Installation-Id" => installation.installation_id } }

  # /api/v1/auth/me is the cheapest authenticated endpoint (SessionsController).
  def authenticated_request(headers = {})
    get "/api/v1/auth/me", headers: headers
  end

  describe "without the header" do
    let!(:installation) { create(:app_installation, :anonymous) }

    it "never touches AppInstallation" do
      expect(AppInstallation).not_to receive(:find_by)

      sign_in user
      authenticated_request

      expect(response).to have_http_status(:ok)
      expect(installation.reload.user_id).to be_nil
      expect(installation.last_authenticated_at).to be_nil
    end
  end

  describe "with the header but no authenticated user" do
    let!(:installation) { create(:app_installation, :anonymous) }

    it "does not associate anyone" do
      authenticated_request(header)

      # Devise bounces the anonymous request (302 to sign_in), never reaching the action.
      expect(response).not_to have_http_status(:ok)
      expect(installation.reload.user_id).to be_nil
      expect(installation.last_authenticated_at).to be_nil
    end
  end

  describe "when the installation is anonymous" do
    let!(:installation) { create(:app_installation, :anonymous) }

    it "associates it to the current user and stamps last_authenticated_at" do
      sign_in user
      authenticated_request(header)

      expect(response).to have_http_status(:ok)
      installation.reload
      expect(installation.user_id).to eq(user.id)
      expect(installation.last_authenticated_at).to be_present
    end

    it "also reconciles through controllers inheriting Api::V1::BaseController" do
      sign_in user
      get "/api/v1/health_profile", headers: header

      expect(installation.reload.user_id).to eq(user.id)
    end
  end

  describe "when the installation already belongs to the same user" do
    let!(:installation) do
      create(:app_installation, user: user, last_authenticated_at: 3.hours.ago)
    end

    it "keeps user_id and refreshes last_authenticated_at once the interval elapsed" do
      previous = installation.last_authenticated_at

      sign_in user
      authenticated_request(header)

      installation.reload
      expect(installation.user_id).to eq(user.id)
      expect(installation.last_authenticated_at).to be > previous
    end

    it "skips the write while inside the touch interval" do
      installation.update_columns(last_authenticated_at: 5.minutes.ago)
      installation.reload
      previous_auth = installation.last_authenticated_at
      previous_updated = installation.updated_at

      sign_in user
      authenticated_request(header)

      installation.reload
      expect(installation.last_authenticated_at).to eq(previous_auth)
      expect(installation.updated_at).to eq(previous_updated)
    end
  end

  describe "when the installation belongs to another user" do
    let(:owner) { create(:user) }
    let!(:installation) do
      create(:app_installation, user: owner, last_authenticated_at: 3.hours.ago)
    end

    it "never overwrites the owner and logs the conflict" do
      installation.reload
      previous = installation.last_authenticated_at
      allow(Rails.logger).to receive(:warn)

      sign_in user
      authenticated_request(header)

      installation.reload
      expect(installation.user_id).to eq(owner.id)
      expect(installation.last_authenticated_at).to eq(previous)
      expect(Rails.logger).to have_received(:warn).with(/association_conflict/)
    end
  end

  describe "when the installation_id is unknown" do
    it "does not create a record and does not break the response" do
      sign_in user

      expect do
        authenticated_request("X-Installation-Id" => "never-registered-#{SecureRandom.uuid}")
      end.not_to change(AppInstallation, :count)

      expect(response).to have_http_status(:ok)
    end
  end
end

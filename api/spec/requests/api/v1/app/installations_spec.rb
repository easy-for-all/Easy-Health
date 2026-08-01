require "rails_helper"

RSpec.describe "Api::V1::App::Installations", type: :request do
  before { allow(AppInstallations::Register).to receive(:enabled?).and_return(true) }

  def payload(overrides = {})
    {
      installation_id: "inst-req-1",
      platform: "android",
      native: true,
      app_version: "1.2.0",
      app_build: "42",
      operating_system: "android",
      operating_system_version: "15",
      locale: "pt-BR",
      timezone: "America/Sao_Paulo",
      notification_permission: "granted",
      push_enabled: true,
      analytics_consent: true,
      tracking_version: 2
    }.merge(overrides)
  end

  def body
    JSON.parse(response.body)
  end

  describe "POST /api/v1/app/installations/register" do
    it "registers an anonymous installation" do
      post "/api/v1/app/installations/register", params: payload, as: :json

      expect(response).to have_http_status(:created)
      install = AppInstallation.find_by(installation_id: "inst-req-1")
      expect(install).to be_present
      expect(install.user_id).to be_nil
      expect(install.platform).to eq("android")
    end

    # The client decides from the body whether the row exists. "2xx" alone is
    # not an answer: a 202 is an acceptance that wrote nothing.
    describe "response contract" do
      it "claims registered=true only when the row was persisted" do
        post "/api/v1/app/installations/register", params: payload, as: :json

        expect(response).to have_http_status(:created)
        expect(body).to include(
          "status" => "registered",
          "registered" => true,
          "installation_id" => "inst-req-1",
          "created" => true
        )
        expect(body["link_status"]).to be_nil
      end

      it "reports the link outcome on an authenticated register" do
        sign_in create(:user)
        post "/api/v1/app/installations/register", params: payload, as: :json

        expect(body["registered"]).to be(true)
        expect(body["link_status"]).to eq("linked")
      end

      it "reports an already-linked installation without re-linking" do
        user = create(:user)
        create(:app_installation, installation_id: "inst-req-1", user: user, linked_at: 1.day.ago)
        sign_in user

        post "/api/v1/app/installations/register", params: payload, as: :json

        expect(response).to have_http_status(:ok)
        expect(body).to include("status" => "registered", "created" => false, "link_status" => "already_linked")
      end

      # The only signal the client gets that its installation_id belongs to
      # somebody else. Without it the app cannot tell a restored id from a
      # healthy one, which is how a new Android user ended up with no
      # AppInstallation at all: the register answered 200/registered and the
      # conflict was invisible.
      it "reports a conflict without transferring ownership" do
        owner = create(:user)
        create(:app_installation, installation_id: "inst-req-1", user: owner, linked_at: 1.day.ago)
        newcomer = create(:user)
        sign_in newcomer

        post "/api/v1/app/installations/register", params: payload, as: :json

        expect(response).to have_http_status(:ok)
        expect(body).to include(
          "status" => "registered", "registered" => true, "link_status" => "conflict"
        )
        # The row still belongs to the original owner — the client regenerating
        # its id is the recovery, never the backend giving the row away.
        install = AppInstallation.find_by(installation_id: "inst-req-1")
        expect(install.user_id).to eq(owner.id)
        expect(install.last_link_failure_code).to eq("user_conflict")
      end

      it "links a regenerated installation_id to the user the conflict blocked" do
        owner = create(:user)
        create(:app_installation, installation_id: "inst-req-1", user: owner, linked_at: 1.day.ago)
        newcomer = create(:user)
        sign_in newcomer

        post "/api/v1/app/installations/register", params: payload, as: :json
        # What the client does next: a brand new id, registered once. (sign_in is
        # per-request in this harness, hence the repeat.)
        sign_in newcomer
        post "/api/v1/app/installations/register",
             params: payload(installation_id: "inst-req-1-regenerated"), as: :json

        expect(body["link_status"]).to eq("linked")
        expect(AppInstallation.find_by(installation_id: "inst-req-1-regenerated").user_id)
          .to eq(newcomer.id)
        # …and the original installation is untouched.
        expect(AppInstallation.find_by(installation_id: "inst-req-1").user_id).to eq(owner.id)
      end

      it "answers deferred (not registered) when the register could not persist" do
        allow_any_instance_of(AppInstallations::Register).to receive(:call).and_return(
          AppInstallations::Register::Result.new(
            installation: nil, created: false, ok: false, status: :unexpected_error
          )
        )

        post "/api/v1/app/installations/register", params: payload, as: :json

        expect(response).to have_http_status(:accepted)
        expect(body).to include("status" => "deferred", "registered" => false, "retryable" => true)
      end

      it "answers disabled — not registered and not retryable — when the flag is off" do
        allow(AppInstallations::Register).to receive(:enabled?).and_return(false)

        post "/api/v1/app/installations/register", params: payload, as: :json

        expect(response).to have_http_status(:accepted)
        expect(body).to include("status" => "disabled", "registered" => false, "retryable" => false)
        expect(AppInstallation.count).to eq(0)
      end

      it "answers validation_failed without inviting a retry" do
        post "/api/v1/app/installations/register", params: payload(platform: "iphone"), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(body).to include(
          "status" => "validation_failed", "registered" => false, "retryable" => false
        )
      end

      it "surfaces a rejected payload from the service as 422, never as success" do
        allow_any_instance_of(AppInstallations::Register).to receive(:call).and_return(
          AppInstallations::Register::Result.new(
            installation: nil, created: false, ok: false, status: :validation_failed
          )
        )

        post "/api/v1/app/installations/register", params: payload, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(body).to include("status" => "validation_failed", "retryable" => false)
      end

      it "never leaks anything but the link outcome" do
        sign_in create(:user)
        post "/api/v1/app/installations/register", params: payload, as: :json

        expect(body.keys).to match_array(%w[status registered installation_id created link_status])
      end
    end

    it "associates the current user server-side, ignoring any client user_id" do
      user = create(:user)
      other = create(:user)
      sign_in user

      post "/api/v1/app/installations/register",
           params: payload(user_id: other.id), as: :json

      expect(AppInstallation.find_by(installation_id: "inst-req-1").user_id).to eq(user.id)
    end

    it "is idempotent (second call updates, returns ok not created)" do
      post "/api/v1/app/installations/register", params: payload, as: :json
      post "/api/v1/app/installations/register", params: payload(app_version: "2.0.0"), as: :json

      expect(response).to have_http_status(:ok)
      expect(AppInstallation.where(installation_id: "inst-req-1").count).to eq(1)
      expect(AppInstallation.find_by(installation_id: "inst-req-1").app_version).to eq("2.0.0")
    end

    it "requires an installation_id" do
      post "/api/v1/app/installations/register", params: payload(installation_id: ""), as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a platform outside the allowlist (422, not a silent coerce)" do
      post "/api/v1/app/installations/register", params: payload(platform: "iphone"), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(AppInstallation.count).to eq(0)
    end

    it "rejects an oversized installation_id (422)" do
      post "/api/v1/app/installations/register", params: payload(installation_id: "x" * 200), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(AppInstallation.count).to eq(0)
    end

    it "sets activation_platform=android on the associated user for a native install" do
      user = create(:user)
      sign_in user

      post "/api/v1/app/installations/register", params: payload(installation_id: "inst-ap-req"), as: :json

      expect(response).to have_http_status(:created)
      expect(user.reload.activation_platform).to eq("android")
    end

    it "stamps last_session_at only when session_started is sent" do
      post "/api/v1/app/installations/register",
           params: payload(installation_id: "inst-boot", session_started: true), as: :json
      expect(AppInstallation.find_by(installation_id: "inst-boot").last_session_at).to be_present

      post "/api/v1/app/installations/register",
           params: payload(installation_id: "inst-plain"), as: :json
      expect(AppInstallation.find_by(installation_id: "inst-plain").last_session_at).to be_nil
    end

    it "never persists when the flag is off (accepts silently)" do
      allow(AppInstallations::Register).to receive(:enabled?).and_return(false)
      post "/api/v1/app/installations/register", params: payload, as: :json
      expect(response).to have_http_status(:accepted)
      expect(AppInstallation.count).to eq(0)
    end

    it "stays non-blocking and observable on an unexpected internal error" do
      allow(Sentry).to receive(:initialized?).and_return(true)
      allow_any_instance_of(AppInstallations::Register).to receive(:call).and_raise(StandardError, "boom")
      expect(Sentry).to receive(:capture_exception)
      expect(Rails.logger).to receive(:error).with(/installations. endpoint error/)

      post "/api/v1/app/installations/register", params: payload, as: :json

      # Never a 500 (must not break the app), never a false success.
      expect(response).to have_http_status(:accepted)
      expect(body).to include("status" => "deferred", "registered" => false, "retryable" => true)
    end
  end

  describe "PATCH /api/v1/app/installations/:installation_id" do
    it "updates permission/consent for an existing install" do
      create(:app_installation, installation_id: "inst-patch", push_enabled: false)

      patch "/api/v1/app/installations/inst-patch",
            params: { notification_permission: "denied", push_enabled: false }, as: :json

      expect(response).to have_http_status(:ok)
      install = AppInstallation.find_by(installation_id: "inst-patch")
      expect(install.notification_permission).to eq("denied")
    end

    it "never stamps last_session_at on a refresh, even if the client sends the flag" do
      create(:app_installation, installation_id: "inst-refresh", last_session_at: nil)

      patch "/api/v1/app/installations/inst-refresh",
            params: { session_started: true, push_enabled: false }, as: :json

      expect(AppInstallation.find_by(installation_id: "inst-refresh").last_session_at).to be_nil
    end
  end
end

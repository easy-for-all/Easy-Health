require "rails_helper"

RSpec.describe Observability::Events do
  # The e-mail counterparts of google_auth_*. Everything they carry has to be an
  # enum, a boolean or an opaque id — the actions that emit them receive an
  # e-mail and a password in params, and none of it may reach a dimension.
  describe "e-mail authentication" do
    after { Observability::Context.reset }

    def event(name)
      ProductAnalyticsEvent.find_by(event_name: name)
    end

    it "records the arrival with the intent and nothing else identifying" do
      described_class.email_auth_started(intent: "login", auth_attempt_id: "attempt-1")

      expect(event("email_auth_started").properties).to include(
        "auth_provider" => "email", "auth_intent" => "login", "auth_attempt_id" => "attempt-1"
      )
    end

    it "attributes the success to the user without writing their identity into properties" do
      user = create(:user)

      described_class.email_auth_succeeded(intent: "sign_up", user: user, auth_attempt_id: "attempt-2")

      row = event("email_auth_succeeded")
      expect(row.user_id).to eq(user.id)
      expect(row.properties.to_json).not_to include(user.email)
    end

    it "coerces a failure category outside the vocabulary to unknown" do
      described_class.email_auth_failed(intent: "login", failure_category: "wrong password for marcus@x.com")

      expect(event("email_auth_failed").properties["failure_category"]).to eq("unknown")
    end

    it "keeps every documented category" do
      described_class::EMAIL_AUTH_FAILURES.each do |category|
        ProductAnalyticsEvent.where(event_name: "email_auth_failed").delete_all
        described_class.email_auth_failed(intent: "login", failure_category: category)

        expect(event("email_auth_failed").properties["failure_category"]).to eq(category)
      end
    end

    it "coerces an unknown intent instead of minting a new dimension value" do
      described_class.email_auth_started(intent: "whatever")

      expect(event("email_auth_started").properties["auth_intent"]).to eq("unknown")
    end

    # An absent attempt id must stay absent: "unknown" would make a client that
    # never sent the header indistinguishable from one whose header was rejected.
    it "omits the attempt id entirely when the client did not send one" do
      described_class.email_auth_started(intent: "login")

      expect(event("email_auth_started").properties).not_to have_key("auth_attempt_id")
    end

    it "joins the event to the installation that produced it" do
      installation = create(:app_installation, platform: "android")
      Observability::Context.installation_id = installation.installation_id

      described_class.email_auth_started(intent: "sign_up")

      expect(event("email_auth_started").properties["installation_id"]).to eq(installation.installation_id)
    end

    it "never raises: telemetry is a diagnostic, not a business rule" do
      allow(Analytics::ServerEvents).to receive(:record).and_raise(StandardError, "sink down")

      expect { described_class.email_auth_started(intent: "login") }.not_to raise_error
    end
  end
end

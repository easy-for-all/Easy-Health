require "rails_helper"

RSpec.describe "Admin observability", type: :request do
  let(:admin) { create(:user, :admin) }

  def payload
    JSON.parse(response.body)
  end

  describe "authorization" do
    it "rejects an anonymous caller" do
      get "/api/v1/admin/observability"

      # Devise redirects unauthenticated callers rather than returning 401 here;
      # what matters is that the payload is never served.
      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("overall_status")
    end

    it "rejects a signed-in non-admin" do
      sign_in create(:user)
      get "/api/v1/admin/observability"

      expect(response).to have_http_status(:forbidden)
    end

    it "allows an admin" do
      sign_in admin
      get "/api/v1/admin/observability"

      expect(response).to have_http_status(:ok)
    end

    it "protects the timeline the same way" do
      sign_in create(:user)
      get "/api/v1/admin/observability/timeline", params: { user_id: 1 }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/admin/observability" do
    before { sign_in admin }

    it "returns EXACTLY six cards, in the documented order" do
      get "/api/v1/admin/observability"

      cards = payload["cards"]
      expect(cards.keys.size).to eq(6)
      expect(cards.keys).to eq(%w[
        api_infrastructure android_registration android_linkage
        google_auth jobs_integrations open_incidents
      ])
    end

    it "returns the documented top-level keys" do
      get "/api/v1/admin/observability"

      expect(payload.keys).to include(
        "generated_at", "overall_status", "cards", "incidents",
        "android_builds", "heartbeats", "thresholds", "data_quality"
      )
    end

    it "never reports a value for a card it could not measure" do
      get "/api/v1/admin/observability"

      payload["cards"].each_value do |card|
        expect(card["value"]).to be_nil if card["status"] == "insufficient_data"
      end
    end

    it "exposes the thresholds the panel is being judged by" do
      get "/api/v1/admin/observability"

      expect(payload["thresholds"]).to include("android_link_warning_rate", "min_android_sample")
    end

    it "does not leak secrets through the thresholds block" do
      with_env("OBSERVABILITY_ALERT_WEBHOOK_TOKEN" => "super-secret-token",
               "OBSERVABILITY_ALERT_WEBHOOK_URL" => "https://hook.test/secret") do
        get "/api/v1/admin/observability"

        expect(response.body).not_to include("super-secret-token")
        expect(response.body).not_to include("hook.test")
      end
    end

    it "accepts a range filter" do
      get "/api/v1/admin/observability", params: { range: "7d" }

      expect(payload["range"]).to eq("7d")
    end

    context "with real data" do
      before do
        12.times do
          AppInstallation.create!(
            installation_id: SecureRandom.uuid, platform: "android",
            app_build: "51", app_version: "1.0.51"
          )
        end
        Observability::HealthCheckRunner.new.call
      end

      it "surfaces the android build table" do
        get "/api/v1/admin/observability", params: { refresh: "1" }

        row = payload["android_builds"].first
        expect(row["app_build"]).to eq("51")
        expect(row["installations"]).to eq(12)
        expect(row["anonymous"]).to eq(12)
        expect(row["linkage_rate"]).to eq(0.0)
      end

      it "returns null rates for a build below the sample floor" do
        AppInstallation.create!(
          installation_id: SecureRandom.uuid, platform: "android",
          app_build: "99", app_version: "1.0.99"
        )

        get "/api/v1/admin/observability", params: { refresh: "1" }

        row = payload["android_builds"].find { |r| r["app_build"] == "99" }
        expect(row["linkage_rate"]).to be_nil
        expect(row["status"]).to eq("insufficient_data")
      end
    end
  end

  describe "incidents" do
    before { sign_in admin }

    let!(:incident) do
      ObservabilityIncident.create!(
        fingerprint: SecureRandom.hex(8), source: "internal_check",
        check_key: "android_registration_conversion", title: "queda",
        severity: "critical", status: "open",
        first_detected_at: 1.hour.ago, last_detected_at: 5.minutes.ago
      )
    end

    it "lists and paginates" do
      get "/api/v1/admin/observability/incidents", params: { per_page: 1 }

      expect(payload["incidents"].size).to eq(1)
      expect(payload["pagination"]).to include("page" => 1, "per_page" => 1, "total" => 1)
    end

    it "caps per_page so a caller cannot request the whole table" do
      get "/api/v1/admin/observability/incidents", params: { per_page: 5_000 }

      expect(payload["pagination"]["per_page"]).to eq(100)
    end

    it "filters by severity" do
      get "/api/v1/admin/observability/incidents", params: { severity: "warning" }

      expect(payload["incidents"]).to be_empty
    end

    it "acknowledges and records who did it" do
      post "/api/v1/admin/observability/incidents/#{incident.id}/acknowledge"

      expect(response).to have_http_status(:ok)
      expect(incident.reload.status).to eq("acknowledged")
      expect(incident.acknowledged_by).to eq("admin:#{admin.id}")
    end

    it "resolves and records who did it" do
      post "/api/v1/admin/observability/incidents/#{incident.id}/resolve"

      expect(incident.reload.status).to eq("resolved")
      expect(incident.resolved_by).to eq("admin:#{admin.id}")
      expect(incident.resolved_at).to be_present
    end
  end

  describe "investigation timeline" do
    before { sign_in admin }

    let(:user) { create(:user, email: "investigado@example.com", name: "Pessoa Investigada") }
    let!(:installation) do
      AppInstallation.create!(
        installation_id: "install-under-investigation", platform: "android",
        app_build: "51", app_version: "1.0.51", user: user,
        last_authenticated_at: 1.hour.ago
      )
    end

    before do
      ProductAnalyticsEvent.create!(
        event_name: "google_auth_succeeded", event_version: 1,
        occurred_at: 1.hour.ago, received_at: Time.current,
        user_id: user.id, platform: "android", app_surface: "unknown",
        environment: "test", source: "easyhealth_backend",
        properties: { "auth_flow" => "native", "result" => "success", "email" => "investigado@example.com" }
      )
    end

    it "requires a subject" do
      get "/api/v1/admin/observability/timeline"

      expect(response).to have_http_status(:bad_request)
    end

    it "returns the journey for a user id" do
      get "/api/v1/admin/observability/timeline", params: { user_id: user.id }

      expect(payload["subject"]["user_ref"]).to eq("u_#{user.id}")
      expect(payload["events"].first["event_name"]).to eq("google_auth_succeeded")
      expect(payload["events"].first["auth_flow"]).to eq("native")
    end

    it "resolves a user from an installation id" do
      get "/api/v1/admin/observability/timeline", params: { installation_id: "install-under-investigation" }

      expect(payload["subject"]["installation_found"]).to be(true)
      expect(payload["subject"]["installation_linked"]).to be(true)
      # Descriptive cohort only. Without OBSERVABILITY_CURRENT_BUILD_MIN set,
      # every numeric build reports as "reported" rather than being ranked.
      expect(payload["subject"]["build_group"]).to eq("reported")
    end

    it "never returns the email or name, even when an event property carries one" do
      get "/api/v1/admin/observability/timeline", params: { user_id: user.id }

      expect(response.body).not_to include("investigado@example.com")
      expect(response.body).not_to include("Pessoa Investigada")
    end

    it "reports a missing installation without failing" do
      get "/api/v1/admin/observability/timeline", params: { installation_id: "does-not-exist" }

      expect(response).to have_http_status(:ok)
      expect(payload["subject"]["installation_found"]).to be(false)
      expect(payload["events"]).to be_empty
    end

    # This branch used to match session_id against an installation_id — two
    # unrelated uuids — so it silently returned nothing and every pre-signup
    # investigation had to be done by hand, by timestamp.
    context "anonymous installation, before any account exists" do
      let!(:anonymous_installation) do
        AppInstallation.create!(
          installation_id: "install-still-anonymous", platform: "android",
          app_build: "50", app_version: "1.0.50"
        )
      end

      def anonymous_event(name, occurred_at, properties = {})
        ProductAnalyticsEvent.create!(
          event_name: name, event_version: 1,
          occurred_at: occurred_at, received_at: Time.current,
          user_id: nil, platform: "android", app_surface: "native_shell",
          environment: "test", source: "web_client",
          anonymous_id: "anon-x", session_id: "session-not-the-installation-id",
          properties: properties.merge("installation_id" => "install-still-anonymous")
        )
      end

      before do
        anonymous_event("app_first_open", 30.minutes.ago)
        anonymous_event("landing_page_viewed", 29.minutes.ago)
        anonymous_event("auth_screen_viewed", 28.minutes.ago, "auth_screen" => "sign_up")
        anonymous_event("auth_client_error", 27.minutes.ago,
                        "stage" => "google_plugin", "error_code" => "plugin_init_failed")
      end

      it "finds the pre-auth journey by installation_id" do
        get "/api/v1/admin/observability/timeline",
            params: { installation_id: "install-still-anonymous" }

        expect(response).to have_http_status(:ok)
        names = payload["events"].map { |e| e["event_name"] }
        expect(names).to contain_exactly(
          "app_first_open", "landing_page_viewed", "auth_screen_viewed", "auth_client_error"
        )
      end

      it "answers where the user stopped and why" do
        get "/api/v1/admin/observability/timeline",
            params: { installation_id: "install-still-anonymous" }

        failure = payload["events"].find { |e| e["event_name"] == "auth_client_error" }
        expect(failure["stage"]).to eq("google_plugin")
        expect(failure["error_code"]).to eq("plugin_init_failed")

        screen = payload["events"].find { |e| e["event_name"] == "auth_screen_viewed" }
        expect(screen["auth_screen"]).to eq("sign_up")
      end

      it "does not pull in another installation's events" do
        anonymous_installation # referenced so the let! is not the only anchor
        ProductAnalyticsEvent.create!(
          event_name: "app_first_open", event_version: 1,
          occurred_at: 20.minutes.ago, received_at: Time.current,
          platform: "android", app_surface: "native_shell", environment: "test",
          properties: { "installation_id" => "some-other-install" }
        )

        get "/api/v1/admin/observability/timeline",
            params: { installation_id: "install-still-anonymous" }

        expect(payload["events"].count { |e| e["event_name"] == "app_first_open" }).to eq(1)
      end
    end

    it "joins the anonymous events to the account once the installation is linked" do
      ProductAnalyticsEvent.create!(
        event_name: "app_first_open", event_version: 1,
        occurred_at: 2.hours.ago, received_at: Time.current,
        user_id: nil, platform: "android", app_surface: "native_shell",
        environment: "test", source: "web_client",
        properties: { "installation_id" => "install-under-investigation" }
      )

      get "/api/v1/admin/observability/timeline",
          params: { installation_id: "install-under-investigation" }

      names = payload["events"].map { |e| e["event_name"] }
      expect(names).to include("app_first_open")      # anonymous, pre-account
      expect(names).to include("google_auth_succeeded") # after the account existed
    end
  end
end

require "rails_helper"

RSpec.describe "Observability checks" do
  def install(build:, linked:, created_at: 1.hour.ago, authenticated_at: nil,
              first_authenticated_request_at: nil, linked_at: nil)
    AppInstallation.create!(
      installation_id: SecureRandom.uuid,
      platform: "android",
      app_build: build,
      app_version: "1.0.#{build}",
      user: linked ? create(:user) : nil,
      last_authenticated_at: authenticated_at,
      first_authenticated_request_at: first_authenticated_request_at,
      linked_at: linked_at,
      created_at: created_at,
      updated_at: created_at
    )
  end

  describe Observability::Checks::AndroidRegistrationConversionCheck do
    it "reports insufficient_data — not 0% — when there is no traffic" do
      results = described_class.run

      expect(results.size).to eq(1)
      expect(results.first.status).to eq("insufficient_data")
      # The whole point: an empty denominator must not become a confident zero.
      expect(results.first.current_value).to be_nil
      expect(results.first.explanation).to include("Nenhuma instalação")
    end

    it "reports insufficient_data for a cohort below the sample floor" do
      3.times { install(build: "51", linked: false) }

      result = described_class.run.find { |r| r.dimensions["build_group"] == "reported" }
      expect(result.status).to eq("insufficient_data")
      expect(result.current_value).to be_nil
      expect(result.sample_size).to eq(3)
    end

    it "flags a critical conversion once the sample is large enough" do
      12.times { install(build: "51", linked: false) }
      1.times { install(build: "51", linked: true) }

      result = described_class.run.find { |r| r.dimensions["build_group"] == "reported" }
      expect(result.status).to eq("critical")
      expect(result.current_value).to be_within(0.01).of(1.0 / 13)
      expect(result.sample_size).to eq(13)
    end

    it "can split a configured current build cohort as descriptive release metadata" do
      with_env("OBSERVABILITY_CURRENT_BUILD_MIN" => "50") do
        15.times { install(build: "10", linked: false) }
        12.times { install(build: "51", linked: true) }

        results = described_class.run
        current = results.find { |r| r.dimensions["build_group"] == "current" }
        reported = results.find { |r| r.dimensions["build_group"] == "reported" }

        expect(current.status).to eq("healthy")
        expect(reported.status).to eq("critical")
      end
    end
  end

  describe Observability::Checks::AndroidInstallationLinkCheck do
    it "opens a critical result for an authenticated-but-unlinked install regardless of sample size" do
      # A single old observed request is enough: it reached the decision point
      # and still has no linked_at.
      install(build: "51", linked: false, first_authenticated_request_at: 30.minutes.ago)

      result = described_class.run.find { |r| r.check_key == "authenticated_without_installation_link" }
      expect(result.status).to eq("critical")
      expect(result.current_value).to eq(1)
    end

    it "tolerates a very recent authentication (write skew window)" do
      install(build: "51", linked: false, first_authenticated_request_at: 10.seconds.ago)

      result = described_class.run.find { |r| r.check_key == "authenticated_without_installation_link" }
      expect(result.status).to eq("healthy")
    end

    it "includes every build once the authenticated request was observed" do
      20.times { install(build: "10", linked: false, first_authenticated_request_at: 1.hour.ago) }

      result = described_class.run.find { |r| r.check_key == "android_installation_link_rate" }
      expect(result.status).to eq("critical")
      expect(result.sample_size).to eq(20)
    end

    # A link created before linked_at existed has a user_id and no linked_at.
    # It is linked, and alerting on it forever would be a permanent false alarm.
    it "never treats a legacy link (user_id without linked_at) as an orphan" do
      install(build: "51", linked: true, first_authenticated_request_at: 2.hours.ago, linked_at: nil)

      result = described_class.run.find { |r| r.check_key == "authenticated_without_installation_link" }
      expect(result.status).to eq("healthy")
      expect(result.current_value).to eq(0)
    end

    it "counts a legacy link in the numerator of the link rate" do
      10.times { install(build: "51", linked: true, first_authenticated_request_at: 1.hour.ago, linked_at: nil) }
      10.times do
        install(build: "51", linked: true, first_authenticated_request_at: 1.hour.ago, linked_at: 1.hour.ago)
      end

      result = described_class.run.find { |r| r.check_key == "android_installation_link_rate" }
      expect(result.status).to eq("healthy")
      expect(result.current_value).to eq(1.0)
      expect(result.sample_size).to eq(20)
    end

    it "still alerts on linked_at without a user_id" do
      install(build: "51", linked: false, first_authenticated_request_at: 2.hours.ago, linked_at: 2.hours.ago)

      result = described_class.run.find { |r| r.check_key == "authenticated_without_installation_link" }
      expect(result.status).to eq("critical")
      expect(result.current_value).to eq(1)
    end

    it "defines the orphan by user_id, not by linked_at" do
      result = described_class.run.find { |r| r.check_key == "authenticated_without_installation_link" }
      expect(result.definition).to include("user_id nulo")
    end
  end

  describe Observability::Checks::GoogleAuthHealthCheck do
    def auth_event(name, flow: "native", error_code: nil, intent: "login", terms: false)
      ProductAnalyticsEvent.create!(
        event_name: name,
        event_version: 1,
        occurred_at: 5.minutes.ago,
        received_at: Time.current,
        platform: "android",
        app_surface: "unknown",
        environment: "test",
        source: "easyhealth_backend",
        properties: {
          "auth_flow" => flow, "error_code" => error_code,
          "auth_intent" => intent, "terms_accepted" => terms
        }.compact
      )
    end

    it "reports insufficient_data with no attempts" do
      result = described_class.run.find { |r| r.check_key == "google_auth_error_rate" }

      expect(result.status).to eq("insufficient_data")
      expect(result.current_value).to be_nil
    end

    it "splits web from native so a native-only outage is visible" do
      12.times { auth_event("google_auth_succeeded", flow: "web") }
      12.times { auth_event("google_auth_failed", flow: "native", error_code: "invalid_audience") }

      results = described_class.run.select { |r| r.check_key == "google_auth_error_rate" }
      native = results.find { |r| r.dimensions["auth_flow"] == "native" }
      web = results.find { |r| r.dimensions["auth_flow"] == "web" }

      expect(native.status).to eq("critical")
      expect(native.current_value).to eq(1.0)
      expect(web.status).to eq("healthy")
      expect(native.dimensions["top_error_code"]).to eq("invalid_audience")
    end

    it "treats consent_required on a login as expected, not as an anomaly" do
      5.times { auth_event("google_auth_failed", error_code: "consent_required", intent: "login", terms: false) }

      result = described_class.run.find { |r| r.check_key == "google_auth_consent_anomaly" }
      expect(result.status).to eq("healthy")
      expect(result.dimensions["expected_consent_required"]).to eq(5)
    end

    it "flags consent_required on a sign-up that already accepted the terms" do
      auth_event("google_auth_failed", error_code: "consent_required", intent: "sign_up", terms: true)

      result = described_class.run.find { |r| r.check_key == "google_auth_consent_anomaly" }
      expect(result.status).to eq("critical")
      expect(result.current_value).to eq(1)
    end
  end

  describe Observability::Checks::JobsIntegrationsCheck do
    it "does not alert on a heartbeat that has never had a chance to run" do
      ObservabilityHeartbeat.create!(key: "fresh", category: "job", expected_interval_seconds: 3600)

      result = described_class.run.find { |r| r.check_key == "stale_heartbeat:fresh" }
      expect(result.status).to eq("insufficient_data")
    end

    it "flags a heartbeat that stopped succeeding" do
      ObservabilityHeartbeat.create!(
        key: "stopped", category: "cron", expected_interval_seconds: 3600,
        last_succeeded_at: 5.hours.ago
      )

      result = described_class.run.find { |r| r.check_key == "stale_heartbeat:stopped" }
      expect(result.status).to eq("critical")
    end

    it "does not treat an empty Make queue as a failure" do
      result = described_class.run.find { |r| r.check_key == "make_delivery_backlog" }

      expect(result.status).to eq("healthy")
      expect(result.explanation).to include("Nenhum evento pendente/retrying/sending preso")
    end

    it "counts due retrying and stale sending Make deliveries as backlog" do
      user = create(:user)
      UserEvent.create!(user: user, event_name: "first_workout_completed",
                        occurred_at: Time.current, make_delivery_status: "retrying",
                        make_next_retry_at: 1.minute.ago)
      UserEvent.create!(user: user, event_name: "first_workout_completed",
                        occurred_at: Time.current, make_delivery_status: "retrying",
                        make_next_retry_at: 1.hour.from_now)
      UserEvent.create!(user: user, event_name: "first_workout_completed",
                        occurred_at: Time.current, make_delivery_status: "sending",
                        make_last_attempt_at: MakePendingDeliveryRetry::STALE_SENDING_AFTER.ago - 1.minute)
      UserEvent.create!(user: user, event_name: "first_workout_completed",
                        occurred_at: Time.current, make_delivery_status: "sending",
                        make_last_attempt_at: 1.minute.ago)

      with_env("OBSERVABILITY_MAKE_BACKLOG_WARNING" => "1", "OBSERVABILITY_MAKE_BACKLOG_CRITICAL" => "3") do
        result = described_class.run.find { |r| r.check_key == "make_delivery_backlog" }

        expect(result.status).to eq("warning")
        expect(result.current_value).to eq(2)
        expect(result.explanation).to include("retrying_due=1", "sending_stale=1")
      end
    end

    it "does not count stale sending with terminal relationship_message as delivery backlog" do
      user = create(:user)
      event = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                occurred_at: Time.current, make_delivery_status: "sending",
                                make_last_attempt_at: MakePendingDeliveryRetry::STALE_SENDING_AFTER.ago - 1.minute)
      create(:relationship_message, :skipped, user: user, user_event: event, event_name: event.event_name)

      with_env("OBSERVABILITY_MAKE_BACKLOG_WARNING" => "1", "OBSERVABILITY_MAKE_BACKLOG_CRITICAL" => "3") do
        result = described_class.run.find { |r| r.check_key == "make_delivery_backlog" }

        expect(result.status).to eq("healthy")
        expect(result.current_value).to eq(0)
        expect(result.dimensions["sending_terminal_pending_reconciliation"]).to eq(1)
      end
    end

    it "reports accepted_by_make events with old unknown processing separately" do
      user = create(:user)
      UserEvent.create!(user: user, event_name: "first_workout_completed",
                        occurred_at: 1.hour.ago, created_at: 1.hour.ago,
                        make_delivery_status: "accepted_by_make", make_processing_status: "unknown")

      with_env("OBSERVABILITY_MAKE_BACKLOG_WARNING" => "1", "OBSERVABILITY_MAKE_BACKLOG_CRITICAL" => "3") do
        result = described_class.run.find { |r| r.check_key == "make_processing_unknown_backlog" }

        expect(result.status).to eq("warning")
        expect(result.current_value).to eq(1)
      end
    end

    it "reports insufficient_data for analytics ingestion below the traffic floor" do
      # Low traffic must not read as a broken pipeline.
      result = described_class.run.find { |r| r.check_key == "android_analytics_ingestion_stale" }

      expect(result.status).to eq("insufficient_data")
      expect(result.explanation).to include("piso de tráfego")
    end

    it "stays silent about the replica before its expected hour plus grace" do
      with_env("BI_REPLICA_EXPECTED_HOUR" => "23", "BI_REPLICA_GRACE_MINUTES" => "60") do
        result = described_class.run.find { |r| r.check_key == "replica_refresh_stale" }
        expect(result.status).to eq("insufficient_data")
      end
    end
  end

  describe Observability::HealthCheckRunner do
    it "continues after one check raises" do
      allow(Observability::Checks::GoogleAuthHealthCheck).to receive(:new).and_raise(StandardError, "boom")

      summary = described_class.new.call

      # The broken check degrades to insufficient_data; the others still ran.
      expect(summary.results.map(&:check_key)).to include("android_registration_conversion")
      expect(summary.results.find { |r| r.check_key == "google_auth_error_rate" }.status).to eq("insufficient_data")
    end

    it "persists every result" do
      expect { described_class.new.call }.to change(ObservabilityCheckResult, :count).by_at_least(5)
    end
  end
end

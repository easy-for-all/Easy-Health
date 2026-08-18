require "rails_helper"

RSpec.describe "Api::V1::Integrations::Make::PushDispatches", type: :request do
  let(:dispatch_token) { "make-dispatch-secret" }
  let(:path) { "/api/v1/integrations/make/push_dispatches" }

  # Orchestration enabled + configured token for the whole file; individual
  # examples override as needed.
  around do |example|
    with_env(
      "MAKE_PUSH_ORCHESTRATION_ENABLED" => "true",
      "MAKE_PUSH_DISPATCH_TOKEN" => dispatch_token,
      "MAKE_PUSH_DISPATCH_TOKEN_CURRENT" => nil,
      "MAKE_PUSH_DISPATCH_TOKEN_PREVIOUS" => nil,
      "MAKE_PUSH_RATE_LIMIT_PER_USER" => "50"
    ) { example.run }
  end

  let(:user) do
    u = create(:user)
    u.notification_preferences!.update!(push_enabled: true, workout_reminders_enabled: true)
    u
  end

  before do
    allow_any_instance_of(FirebasePushService).to receive(:deliver).and_return(
      FirebasePushService::Result.new(status: "sent", message_id: "mock/1", invalid_token: false)
    )
  end

  def auth_headers(token = dispatch_token)
    { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" }
  end

  def valid_payload(overrides = {})
    {
      event_id: "evt_#{SecureRandom.hex(4)}",
      user_id: user.id,
      notification_type: "workout_reminder",
      campaign_key: "workout_not_started_v1",
      title: "Seu treino está esperando",
      body: "Que tal começar agora?",
      route: "/workouts/456",
      data: { "workout_id" => "456" }
    }.merge(overrides)
  end

  def post_dispatch(payload, headers: auth_headers)
    post path, params: payload.to_json, headers: headers
  end

  describe "authentication" do
    it "rejects a request with no Authorization header" do
      post path, params: valid_payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a wrong token" do
      post_dispatch(valid_payload, headers: auth_headers("wrong-token"))
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts the PREVIOUS token during rotation" do
      create(:device_token, user: user)
      with_env("MAKE_PUSH_DISPATCH_TOKEN" => "new-token", "MAKE_PUSH_DISPATCH_TOKEN_PREVIOUS" => "old-token") do
        post_dispatch(valid_payload, headers: auth_headers("old-token"))
      end
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("provider_accepted")
    end
  end

  describe "feature flag off" do
    it "returns orchestration_disabled without sending" do
      expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
      with_env("MAKE_PUSH_ORCHESTRATION_ENABLED" => "false") do
        post_dispatch(valid_payload)
      end
      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "skipped", "reason" => "orchestration_disabled", "sent" => false)
    end
  end

  describe "payload validation" do
    it "rejects an unknown notification_type" do
      post_dispatch(valid_payload(notification_type: "spam"))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["reason"]).to eq("invalid_payload")
    end

    it "rejects a missing title" do
      post_dispatch(valid_payload(title: ""))
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a route outside the allowlist" do
      post_dispatch(valid_payload(route: "https://evil.com"))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["detail"]).to eq("route_not_allowed")
    end

    it "rejects HTML/script in the title" do
      post_dispatch(valid_payload(title: "<script>alert(1)</script>"))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["detail"]).to eq("unsafe_content")
    end

    it "rejects a device token supplied by Make" do
      post_dispatch(valid_payload(token: "should-not-be-here"))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["detail"]).to eq("forbidden_token_field")
    end

    it "rejects a token nested inside data" do
      post_dispatch(valid_payload(data: { "device_token" => "sneaky" }))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["detail"]).to eq("forbidden_token_field")
    end

    it "rejects an oversized body" do
      post_dispatch(valid_payload(data: { "x" => "a" * 9000 }))
      expect(response).to have_http_status(:payload_too_large)
    end
  end

  describe "user resolution & preferences" do
    it "returns a neutral skip for a non-existent user" do
      post_dispatch(valid_payload(user_id: 0))
      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "skipped", "reason" => "user_not_found", "sent" => false)
    end

    it "skips with no_preferences when the user never completed the consent flow" do
      no_prefs_user = create(:user)
      create(:device_token, user: no_prefs_user)
      expect(no_prefs_user.notification_preferences).to be_nil

      post_dispatch(valid_payload(user_id: no_prefs_user.id))
      expect(json["reason"]).to eq("no_preferences")
    end

    it "skips global opt-out" do
      user.notification_preferences.update!(push_enabled: false)
      create(:device_token, user: user)
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("global_opt_out")
    end

    it "skips global opt-out when notifications_disabled_at is present" do
      user.notification_preferences.update!(notifications_disabled_at: Time.current)
      create(:device_token, user: user)
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("global_opt_out")
    end

    it "skips category opt-out (reminders disabled)" do
      user.notification_preferences.update!(workout_reminders_enabled: false)
      create(:device_token, user: user)
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("category_opt_out")
    end

    it "skips when the user has no active token" do
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("no_active_token")
    end

    # Pausing the scheduled reminder inactivity policy only stops one producer
    # rule from erasing the event. Delivery is still decided here, and none of
    # these opt-outs may loosen because of that flag.
    describe "with the scheduled reminder inactivity policy paused" do
      around do |example|
        with_env("SCHEDULED_WORKOUT_INACTIVITY_SUPPRESSION_ENABLED" => "false") { example.run }
      end

      it "still skips global opt-out with push disabled" do
        user.notification_preferences.update!(push_enabled: false)
        create(:device_token, user: user)
        post_dispatch(valid_payload)
        expect(json).to include("status" => "skipped", "reason" => "global_opt_out", "sent" => false)
      end

      it "still skips category opt-out with workout reminders disabled" do
        user.notification_preferences.update!(workout_reminders_enabled: false)
        create(:device_token, user: user)
        post_dispatch(valid_payload)
        expect(json).to include("status" => "skipped", "reason" => "category_opt_out", "sent" => false)
      end

      it "still skips global opt-out with notifications_disabled_at present" do
        user.notification_preferences.update!(notifications_disabled_at: Time.current)
        create(:device_token, user: user)
        post_dispatch(valid_payload)
        expect(json).to include("status" => "skipped", "reason" => "global_opt_out", "sent" => false)
      end
    end

    it "skips an invalidated token as no_active_token" do
      create(:device_token, user: user).invalidate!("test")
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("no_active_token")
    end

    it "skips permission_denied when the only token was denied" do
      create(:device_token, user: user, permission_status: "denied")
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("permission_denied")
    end
  end

  describe "successful dispatch" do
    before { create(:device_token, user: user) }

    it "sends and records a provider_accepted dispatch" do
      post_dispatch(valid_payload)

      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "provider_accepted", "sent" => true,
                              "tokens_attempted" => 1, "tokens_accepted" => 1)
      dispatch = PushDispatch.last
      expect(dispatch.status).to eq("provider_accepted")
      expect(dispatch.provider_accepted_at).to be_present
    end

    it "builds FCM data with a single source key and reserved keys winning over Make data" do
      captured = nil
      allow_any_instance_of(FirebasePushService).to receive(:deliver) do |_svc, **kwargs|
        captured = kwargs[:data]
        FirebasePushService::Result.new(status: "sent", message_id: "m", invalid_token: false)
      end

      # Make sends its own workout_id AND tries to override "source".
      post_dispatch(valid_payload(data: { "workout_id" => "456", "source" => "make_scenario" }))

      serialized = JSON.parse(captured.to_json)
      # The duplicate-key bug (:source vs "source") would surface here.
      expect(serialized.keys.count { |k| k == "source" }).to eq(1)
      expect(serialized["source"]).to eq("make")            # reserved key wins
      expect(serialized["target_path"]).to eq("/workouts/456")
      expect(serialized["workout_id"]).to eq("456")         # Make data passes through
    end

    it "never persists a device token in payload_json" do
      post_dispatch(valid_payload(data: { "workout_id" => "456" }))
      expect(PushDispatch.last.payload_json.to_json).not_to include(DeviceToken.last.token)
    end

    it "is idempotent: the same event returns duplicate without re-sending" do
      payload = valid_payload
      post_dispatch(payload)
      expect(json["status"]).to eq("provider_accepted")

      expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
      post_dispatch(payload)
      expect(json).to include("status" => "duplicate", "sent" => false)
      expect(PushDispatch.count).to eq(1)
    end

    it "returns 502 with the Firebase message and does NOT invalidate on INVALID_ARGUMENT" do
      device = user.device_tokens.first
      allow_any_instance_of(FirebasePushService).to receive(:deliver).and_return(
        FirebasePushService::Result.new(
          status: "failed", error_code: "INVALID_ARGUMENT",
          error_message: "The registration token is not a valid FCM registration token",
          invalid_token: false
        )
      )
      post_dispatch(valid_payload)

      expect(response).to have_http_status(:bad_gateway)
      expect(json).to include("status" => "failed", "sent" => false,
                              "last_error_code" => "INVALID_ARGUMENT")
      expect(json["last_error_message"]).to match(/registration token/)
      expect(device.reload.enabled).to be(true)
      expect(PushDispatch.last.last_error_message).to be_present
    end

    it "delivers to a second device when the first is rejected" do
      create(:device_token, user: user)
      allow_any_instance_of(FirebasePushService).to receive(:deliver).and_return(
        FirebasePushService::Result.new(status: "failed", error_code: "http_500", invalid_token: false),
        FirebasePushService::Result.new(status: "sent", message_id: "mock/2", invalid_token: false)
      )
      post_dispatch(valid_payload)
      expect(json["status"]).to eq("partially_accepted")
      expect(json["tokens_rejected"]).to eq(1)
      expect(json["tokens_accepted"]).to eq(1)
    end
  end

  describe "rate limiting" do
    before { create(:device_token, user: user) }

    it "returns rate_limited over the per-user threshold" do
      with_env("MAKE_PUSH_RATE_LIMIT_PER_USER" => "1") do
        PushDispatch.create!(user: user, notification_type: "workout_reminder",
                             idempotency_key: "seed:#{SecureRandom.hex(4)}", status: "provider_accepted")
        post_dispatch(valid_payload)
      end
      expect(response).to have_http_status(:too_many_requests)
      expect(json["reason"]).to eq("rate_limited")
    end
  end

  describe "engagement frequency" do
    before { create(:device_token, user: user) }

    def seed_dispatch(dispatched_at:, notification_type: "workout_reminder", status: "provider_accepted")
      PushDispatch.create!(
        user: user, notification_type: notification_type, status: status,
        idempotency_key: "seed:#{SecureRandom.hex(4)}", dispatched_at: dispatched_at
      )
    end

    it "skips cooldown_active when an engagement push was delivered in the last 20h" do
      seed_dispatch(dispatched_at: 1.hour.ago)
      post_dispatch(valid_payload)
      expect(json).to include("status" => "skipped", "reason" => "cooldown_active", "sent" => false)
    end

    it "skips frequency_capped after 2 engagement pushes in 7 days (outside cooldown)" do
      seed_dispatch(dispatched_at: 2.days.ago)
      seed_dispatch(dispatched_at: 3.days.ago)
      post_dispatch(valid_payload)
      expect(json).to include("status" => "skipped", "reason" => "frequency_capped", "sent" => false)
    end

    it "sends an engagement push when under the cap and cooldown" do
      seed_dispatch(dispatched_at: 4.days.ago)
      post_dispatch(valid_payload)
      expect(json["status"]).to eq("provider_accepted")
    end

    it "exempts first_workout_completed (progress_update) from cooldown and cap" do
      seed_dispatch(dispatched_at: 1.hour.ago)
      seed_dispatch(dispatched_at: 2.days.ago)
      post_dispatch(valid_payload(notification_type: "progress_update", campaign_key: "first_workout_completed",
                                  route: "/workouts"))
      expect(json["status"]).to eq("provider_accepted")
    end
  end

  # Regression guard for the smoke-test incident: the four engagement events were
  # silently dropped while first_workout_completed went through, because
  # progress_update is exempt from BOTH the reminder opt-out and the frequency
  # rules. The skip envelope must make that readable without a DB query.
  describe "skip envelope" do
    before { create(:device_token, user: user) }

    it "reports skip_reason, dispatch_id, notification_type and campaign_key on a preference skip" do
      user.notification_preferences!.update!(workout_reminders_enabled: false)
      post_dispatch(valid_payload(campaign_key: "user-inactive-3-days-v1"))

      expect(response).to have_http_status(:ok)
      expect(json).to include(
        "status" => "skipped",
        "sent" => false,
        "skip_reason" => "category_opt_out",
        "notification_type" => "workout_reminder",
        "campaign_key" => "user-inactive-3-days-v1"
      )
      expect(json["dispatch_id"]).to eq(PushDispatch.last.id)
    end

    it "keeps the legacy reason key as an alias of skip_reason" do
      user.notification_preferences!.update!(push_enabled: false)
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq(json["skip_reason"])
      expect(json["skip_reason"]).to eq("global_opt_out")
    end

    it "reports skip_reason on a cooldown skip" do
      PushDispatch.create!(user: user, notification_type: "workout_reminder", status: "provider_accepted",
                           idempotency_key: "seed:#{SecureRandom.hex(4)}", dispatched_at: 1.hour.ago)
      post_dispatch(valid_payload)
      expect(json).to include("skip_reason" => "cooldown_active", "sent" => false)
    end
  end

  describe "smoke-test frequency bypass" do
    let(:test_token) { "push-test-secret" }

    before do
      create(:device_token, user: user)
      # Cooldown is active: without a bypass every example here would skip.
      PushDispatch.create!(user: user, notification_type: "workout_reminder", status: "provider_accepted",
                           idempotency_key: "seed:#{SecureRandom.hex(4)}", dispatched_at: 1.hour.ago)
    end

    def bypass_payload
      valid_payload(data: { "source" => "manual_push_test", "bypass_engagement_frequency" => true })
    end

    def bypass_headers(token = test_token)
      auth_headers.merge("X-Push-Test-Token" => token)
    end

    def with_bypass_env(enabled: "true", &block)
      with_env("MAKE_PUSH_TEST_BYPASS_ENABLED" => enabled,
               "MAKE_PUSH_TEST_BYPASS_TOKEN" => test_token,
               "MAKE_PUSH_TEST_BYPASS_EMAILS" => user.email, &block)
    end

    context "when every condition holds" do
      before { user.update!(admin: true) }

      it "waives the cooldown and sends" do
        with_bypass_env { post_dispatch(bypass_payload, headers: bypass_headers) }
        expect(json["status"]).to eq("provider_accepted")
        expect(json["sent"]).to be(true)
      end

      # A frequency-only bypass keeps the legacy event name so existing
      # dashboards and queries do not break.
      it "audits the granted bypass" do
        expect {
          with_bypass_env { post_dispatch(bypass_payload, headers: bypass_headers) }
        }.to change { UserEvent.where(event_name: "push_frequency_bypass_granted", user_id: user.id).count }.by(1)
      end

      it "records both capabilities on the audit event" do
        with_bypass_env { post_dispatch(bypass_payload, headers: bypass_headers) }

        metadata = UserEvent.where(event_name: "push_frequency_bypass_granted", user_id: user.id).last.metadata
        expect(metadata).to include(
          "admin" => true,
          "bypass_engagement_frequency" => true,
          "bypass_quiet_hours" => false
        )
        expect(metadata).not_to have_key("denied_reason")
      end

      it "does not leak the bypass flag into the FCM data payload" do
        expect_any_instance_of(FirebasePushService).to receive(:deliver) do |_, args|
          expect(args[:data]).not_to have_key("bypass_engagement_frequency")
          FirebasePushService::Result.new(status: "sent", message_id: "mock/1", invalid_token: false)
        end
        with_bypass_env { post_dispatch(bypass_payload, headers: bypass_headers) }
      end
    end

    context "when a condition is missing" do
      it "refuses for a non-admin user" do
        with_bypass_env { post_dispatch(bypass_payload, headers: bypass_headers) }
        expect(json["skip_reason"]).to eq("cooldown_active")
      end

      it "refuses for an admin who is not on the allowlist" do
        user.update!(admin: true)
        with_env("MAKE_PUSH_TEST_BYPASS_ENABLED" => "true",
                 "MAKE_PUSH_TEST_BYPASS_TOKEN" => test_token,
                 "MAKE_PUSH_TEST_BYPASS_EMAILS" => "someone-else@example.com") do
          post_dispatch(bypass_payload, headers: bypass_headers)
        end
        expect(json["skip_reason"]).to eq("cooldown_active")
      end

      it "refuses when the environment does not enable the bypass" do
        user.update!(admin: true)
        with_bypass_env(enabled: "false") { post_dispatch(bypass_payload, headers: bypass_headers) }
        expect(json["skip_reason"]).to eq("cooldown_active")
      end

      it "refuses when the dispatch bearer is presented without the test token" do
        user.update!(admin: true)
        with_bypass_env { post_dispatch(bypass_payload, headers: auth_headers) }
        expect(json["skip_reason"]).to eq("cooldown_active")
      end

      it "refuses when the test token is wrong" do
        user.update!(admin: true)
        with_bypass_env { post_dispatch(bypass_payload, headers: bypass_headers("nope")) }
        expect(json["skip_reason"]).to eq("cooldown_active")
      end

      it "refuses when the flag is set but source is not manual_push_test" do
        user.update!(admin: true)
        payload = valid_payload(data: { "source" => "make", "bypass_engagement_frequency" => true })
        with_bypass_env { post_dispatch(payload, headers: bypass_headers) }
        expect(json["skip_reason"]).to eq("cooldown_active")
      end

      # A wrong source is an ATTEMPT at a bypass, not a no-op, so it must be
      # visible in the audit trail like every other refusal.
      it "audits a wrong source as invalid_source" do
        user.update!(admin: true)
        payload = valid_payload(data: { "source" => "make", "bypass_engagement_frequency" => true })
        with_bypass_env { post_dispatch(payload, headers: bypass_headers) }

        event = UserEvent.where(event_name: "push_frequency_bypass_denied", user_id: user.id).last
        expect(event.metadata["denied_reason"]).to eq("invalid_source")
      end

      # Fail-closed: an operator mistake in the env must not open the mechanism.
      it "refuses when the e-mail allowlist is empty" do
        user.update!(admin: true)
        with_env("MAKE_PUSH_TEST_BYPASS_ENABLED" => "true",
                 "MAKE_PUSH_TEST_BYPASS_TOKEN" => test_token,
                 "MAKE_PUSH_TEST_BYPASS_EMAILS" => "") do
          post_dispatch(bypass_payload, headers: bypass_headers)
        end
        expect(json["skip_reason"]).to eq("cooldown_active")
      end

      it "audits the refused attempt" do
        expect {
          with_bypass_env { post_dispatch(bypass_payload, headers: bypass_headers) }
        }.to change { UserEvent.where(event_name: "push_frequency_bypass_denied", user_id: user.id).count }.by(1)
      end

      it "records both capabilities on a denied audit event" do
        with_bypass_env { post_dispatch(bypass_payload, headers: bypass_headers) }

        metadata = UserEvent.where(event_name: "push_frequency_bypass_denied", user_id: user.id).last.metadata
        expect(metadata).to include(
          "admin" => false,
          "bypass_engagement_frequency" => true,
          "bypass_quiet_hours" => false,
          "denied_reason" => "user_not_allowlisted"
        )
      end
    end

    it "does not audit anything when no bypass was requested" do
      user.update!(admin: true)
      expect {
        with_bypass_env { post_dispatch(valid_payload, headers: bypass_headers) }
      }.not_to change { UserEvent.where(user_id: user.id).where("event_name LIKE '%bypass%'").count }
    end

    it "never waives consent: an opted-out admin is still skipped" do
      user.update!(admin: true)
      user.notification_preferences!.update!(workout_reminders_enabled: false)
      with_bypass_env { post_dispatch(bypass_payload, headers: bypass_headers) }
      expect(json["skip_reason"]).to eq("category_opt_out")
      expect(json["sent"]).to be(false)
    end

    it "never waives the active-token requirement" do
      user.update!(admin: true)
      user.device_tokens.each { |t| t.invalidate!("test") }
      with_bypass_env { post_dispatch(bypass_payload, headers: bypass_headers) }
      expect(json["skip_reason"]).to eq("no_active_token")
    end
  end

  # The quiet-hours bypass exists so an operator can validate the REAL pipeline
  # (Make -> dispatch -> FCM -> device) at the hour they are holding the phone.
  # It runs on the same shared credential as the frequency bypass and waives
  # nothing else: every example below that is missing one condition must still
  # defer, and no hard gate is ever skipped.
  describe "smoke-test quiet-hours bypass" do
    include ActiveSupport::Testing::TimeHelpers

    let(:test_token) { "push-test-secret" }

    before do
      create(:device_token, user: user, permission_status: "granted")
      user.update!(time_zone: "America/Sao_Paulo")
    end

    # 03:00 in São Paulo — inside the 22:00-07:00 quiet-hours window.
    def at_night(&block)
      travel_to(Time.utc(2026, 7, 20, 6, 0), &block)
    end

    def bypass_payload(overrides = {})
      valid_payload({ data: { "source" => "manual_push_test", "bypass_quiet_hours" => true } }.merge(overrides))
    end

    def bypass_headers(token = test_token)
      auth_headers.merge("X-Push-Test-Token" => token)
    end

    def with_bypass_env(enabled: "true", emails: nil, token: nil, &block)
      with_env("PUSH_QUIET_HOURS_ENABLED" => "true",
               "MAKE_PUSH_TEST_BYPASS_ENABLED" => enabled,
               "MAKE_PUSH_TEST_BYPASS_TOKEN" => token || test_token,
               "MAKE_PUSH_TEST_BYPASS_EMAILS" => emails || user.email, &block)
    end

    # Runs the request at night with the gate on; yields nothing, asserts later.
    def post_at_night(payload = bypass_payload, headers: bypass_headers, **env)
      at_night { with_bypass_env(**env) { post_dispatch(payload, headers: headers) } }
    end

    context "A) when every condition holds" do
      before { user.update!(admin: true) }

      it "sends immediately instead of deferring" do
        post_at_night

        expect(response).to have_http_status(:ok)
        expect(json).to include("status" => "provider_accepted", "sent" => true)
        expect(json["deferred"]).to be_nil
        dispatch = PushDispatch.last
        expect(dispatch.status).to eq("provider_accepted")
        expect(dispatch.next_allowed_at).to be_nil
        expect(dispatch.provider_accepted_at).to be_present
      end

      it "audits under the generic push_test_bypass name, not the frequency one" do
        expect { post_at_night }
          .to change { UserEvent.where(event_name: "push_test_bypass_granted", user_id: user.id).count }.by(1)
        expect(UserEvent.where(event_name: "push_frequency_bypass_granted").count).to eq(0)

        metadata = UserEvent.where(event_name: "push_test_bypass_granted", user_id: user.id).last.metadata
        expect(metadata).to include(
          "admin" => true,
          "bypass_quiet_hours" => true,
          "bypass_engagement_frequency" => false,
          "notification_type" => "workout_reminder"
        )
      end
    end

    # B-H: one condition missing at a time. Every case must behave exactly like
    # a normal user at 03:00 — deferred, never sent.
    context "when a condition is missing" do
      def expect_deferred
        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
        yield
        expect(json["status"]).to eq("deferred")
        expect(json["defer_reason"]).to eq("quiet_hours")
        expect(json["sent"]).to be(false)
        expect(PushDispatch.last.status).to eq("deferred")
      end

      it "B) keeps quiet hours for a non-admin user" do
        expect_deferred { post_at_night }
      end

      it "C) keeps quiet hours for an admin outside the allowlist" do
        user.update!(admin: true)
        expect_deferred { post_at_night(emails: "someone-else@example.com") }
      end

      it "D) keeps quiet hours when the test token header is absent" do
        user.update!(admin: true)
        expect_deferred { post_at_night(headers: auth_headers) }
      end

      it "E) keeps quiet hours when the test token is wrong" do
        user.update!(admin: true)
        expect_deferred { post_at_night(headers: bypass_headers("nope")) }
      end

      it "F) keeps quiet hours when the environment does not enable the bypass" do
        user.update!(admin: true)
        expect_deferred { post_at_night(enabled: "false") }
      end

      it "G) keeps quiet hours when the source is not manual_push_test" do
        user.update!(admin: true)
        payload = valid_payload(data: { "source" => "make", "bypass_quiet_hours" => true })
        expect_deferred { post_at_night(payload) }
      end

      it "G) audits a wrong source as a denied attempt" do
        user.update!(admin: true)
        payload = valid_payload(data: { "source" => "make", "bypass_quiet_hours" => true })
        post_at_night(payload)

        event = UserEvent.where(event_name: "push_test_bypass_denied", user_id: user.id).last
        expect(event.metadata["denied_reason"]).to eq("invalid_source")
        expect(event.metadata["bypass_quiet_hours"]).to be(true)
      end

      it "H) keeps quiet hours when the flag is absent" do
        user.update!(admin: true)
        expect_deferred { post_at_night(valid_payload(data: { "source" => "manual_push_test" })) }
      end

      it "H) keeps quiet hours when the flag is explicitly false" do
        user.update!(admin: true)
        payload = valid_payload(data: { "source" => "manual_push_test", "bypass_quiet_hours" => false })
        expect_deferred { post_at_night(payload) }
      end

      it "H) does not audit when no bypass was requested at all" do
        user.update!(admin: true)
        expect { post_at_night(valid_payload) }
          .not_to change { UserEvent.where(user_id: user.id).where("event_name LIKE '%bypass%'").count }
      end

      # N) The fail-closed guard: ENABLED=true, correct token and a real admin,
      # but an empty allowlist. An operator mistake must not open the mechanism.
      it "N) keeps quiet hours when the e-mail allowlist is empty" do
        user.update!(admin: true)
        expect_deferred { post_at_night(emails: "") }

        event = UserEvent.where(event_name: "push_test_bypass_denied", user_id: user.id).last
        expect(event.metadata["denied_reason"]).to eq("user_not_allowlisted")
        expect(event.metadata["admin"]).to be(true)
      end
    end

    # I-L: a granted bypass waives TIMING only. Consent, category, token and
    # idempotency stay mandatory.
    context "with a valid bypass, the hard gates still apply" do
      before { user.update!(admin: true) }

      it "I) does not waive push_enabled" do
        user.notification_preferences!.update!(push_enabled: false)
        post_at_night

        expect(json).to include("skip_reason" => "global_opt_out", "sent" => false)
        expect(json["deferred"]).to be(false)
      end

      it "J) does not waive the category opt-out" do
        user.notification_preferences!.update!(workout_reminders_enabled: false)
        post_at_night

        expect(json).to include("skip_reason" => "category_opt_out", "sent" => false)
      end

      it "K) does not waive the active-token requirement" do
        user.device_tokens.each { |t| t.invalidate!("test") }
        post_at_night

        expect(json).to include("skip_reason" => "no_active_token", "sent" => false)
      end

      it "K) does not waive a denied device permission" do
        user.device_tokens.each { |t| t.update!(permission_status: "denied") }
        post_at_night

        expect(json).to include("skip_reason" => "permission_denied", "sent" => false)
      end

      it "L) still honours idempotency_key: the same event sends only once" do
        payload = bypass_payload(event_id: "evt_bypass_idem")

        post_at_night(payload)
        expect(json["status"]).to eq("provider_accepted")

        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
        post_at_night(payload)

        expect(json).to include("status" => "duplicate", "sent" => false)
        expect(PushDispatch.where(idempotency_key: payload[:event_id] +
          ":workout_not_started_v1:#{user.id}:workout_reminder").count).to eq(1)
      end
    end

    # M) Test plumbing must never reach the device.
    context "M) FCM payload hygiene" do
      before { user.update!(admin: true) }

      it "strips both bypass flags and never forwards manual_push_test" do
        captured = nil
        allow_any_instance_of(FirebasePushService).to receive(:deliver) do |_svc, **kwargs|
          captured = kwargs[:data]
          FirebasePushService::Result.new(status: "sent", message_id: "mock/1", invalid_token: false)
        end

        payload = bypass_payload(
          data: { "source" => "manual_push_test", "bypass_quiet_hours" => true,
                  "bypass_engagement_frequency" => true, "workout_id" => "456" }
        )
        post_at_night(payload)

        expect(captured).not_to have_key("bypass_quiet_hours")
        expect(captured).not_to have_key("bypass_engagement_frequency")
        # `source` keeps its product meaning; the reserved key wins over Make's.
        expect(captured["source"]).to eq("make")
        expect(captured.to_json).not_to include("manual_push_test")
        expect(captured["workout_id"]).to eq("456")   # real data still passes through
      end
    end

    context "with both capabilities requested at once" do
      before do
        user.update!(admin: true)
        # Cooldown active AND inside quiet hours: both rules would block.
        PushDispatch.create!(user: user, notification_type: "workout_reminder", status: "provider_accepted",
                             idempotency_key: "seed:#{SecureRandom.hex(4)}", dispatched_at: 1.hour.ago)
      end

      def both_payload
        valid_payload(data: { "source" => "manual_push_test", "bypass_quiet_hours" => true,
                              "bypass_engagement_frequency" => true })
      end

      it "sends, and emits exactly one audit event covering both" do
        expect { post_at_night(both_payload) }
          .to change { UserEvent.where(user_id: user.id).where("event_name LIKE '%bypass%'").count }.by(1)

        expect(json).to include("status" => "provider_accepted", "sent" => true)
        metadata = UserEvent.where(event_name: "push_test_bypass_granted", user_id: user.id).last.metadata
        expect(metadata).to include(
          "bypass_engagement_frequency" => true,
          "bypass_quiet_hours" => true
        )
      end
    end
  end

  describe "quiet hours" do
    include ActiveSupport::Testing::TimeHelpers

    let!(:token) { create(:device_token, user: user, permission_status: "granted") }
    let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }

    before { user.update!(time_zone: "America/Sao_Paulo") }

    # 03:00 in São Paulo — inside the 22:00–07:00 quiet-hours window.
    def at_night(&block)
      travel_to(Time.utc(2026, 7, 20, 6, 0), &block)
    end

    it "sends at night when the gate is off, preserving today's behaviour" do
      at_night do
        with_env("PUSH_QUIET_HOURS_ENABLED" => "false") { post_dispatch(valid_payload) }
      end

      expect(json["sent"]).to be(true)
    end

    it "defers at night when the gate is on" do
      expect_any_instance_of(FirebasePushService).not_to receive(:deliver)

      at_night do
        with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
      end

      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("deferred")
      expect(json["defer_reason"]).to eq("quiet_hours")
      expect(json["skip_reason"]).to be_nil
      expect(json["sent"]).to be(false)
    end

    it "records next_allowed_at in the user's timezone" do
      at_night do
        with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
      end

      expect(json["deferred"]).to be(true)
      expect(json["user_timezone"]).to eq("America/Sao_Paulo")

      next_allowed = Time.zone.parse(json["next_allowed_at"])
      expect(next_allowed.in_time_zone("America/Sao_Paulo").hour).to eq(PushQuietHours::END_HOUR)
      expect(next_allowed).to be > Time.utc(2026, 7, 20, 6, 0)
    end

    it "marks a permanent skip as not deferred" do
      user.notification_preferences!.update!(push_enabled: false)

      with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }

      expect(json["skip_reason"]).to eq("global_opt_out")
      expect(json["deferred"]).to be(false)
      expect(json["next_allowed_at"]).to be_nil
    end

    it "persists a non-terminal deferred dispatch row" do
      at_night do
        with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
      end

      dispatch = PushDispatch.last
      expect(dispatch.status).to eq("deferred")
      expect(dispatch.skip_reason).to be_nil
      expect(dispatch.defer_reason).to eq("quiet_hours")
      expect(dispatch.next_allowed_at).to be_present
    end

    it "reuses the same deferred dispatch for the same idempotency key" do
      payload = valid_payload(event_id: "evt_same")

      at_night do
        with_env("PUSH_QUIET_HOURS_ENABLED" => "true") do
          post_dispatch(payload)
          post_dispatch(payload)
        end
      end

      expect(PushDispatch.where(idempotency_key: "evt_same:workout_not_started_v1:#{user.id}:workout_reminder").count).to eq(1)
      expect(json["status"]).to eq("deferred")
    end

    it "dispatches a deferred push after quiet hours and revalidates gates" do
      at_night do
        with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
      end

      dispatch = PushDispatch.last
      travel_to(Time.utc(2026, 7, 20, 11, 0)) do # 08:00 São Paulo
        stats = Make::PushDispatchRequest.dispatch_deferred(now: Time.current)
        expect(stats[:sent]).to eq(1)
      end

      expect(dispatch.reload.status).to eq("provider_accepted")
    end

    it "sends during the day with the gate on" do
      travel_to(Time.utc(2026, 7, 20, 13, 0)) do # 10:00 São Paulo
        with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
      end

      expect(json["sent"]).to be(true)
    end

    it "does not count a deferred dispatch toward cooldown" do
      at_night do
        with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
      end

      travel_to(Time.utc(2026, 7, 20, 13, 0)) do
        with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload(event_id: "evt_after_quiet")) }
      end

      expect(json["sent"]).to be(true)
    end

    # A scheduled reminder may cross quiet hours, but ONLY inside the explicit
    # reminder_due_at -> target_workout_at window. This event carries no
    # reminder_due_at, so there is no window to grant the exception on and the
    # conservative behaviour stands: deferring would release at 07:00, which is
    # already the workout time.
    it "skips a 07:00 workout reminder with no explicit window, made stale by quiet hours" do
      event = user.user_events.create!(
        event_name: "scheduled_workout_reminder_due",
        occurred_at: Time.current,
        metadata: {
          activation: {
            target_workout_at: zone.local(2026, 7, 20, 7, 0).iso8601
          }
        }
      )
      payload = valid_payload(
        event_id: event.id.to_s,
        campaign_key: "scheduled_workout_reminder_due",
        data: { "event_name" => "scheduled_workout_reminder_due" }
      )

      travel_to(zone.local(2026, 7, 20, 6, 30)) do
        with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(payload) }
      end

      expect(json["status"]).to eq("skipped")
      expect(json["skip_reason"]).to eq("stale_after_quiet_hours")
      expect(PushDispatch.last.skip_reason).to eq("stale_after_quiet_hours")
    end

    it "sends a 07:30 workout reminder at 07:00" do
      event = user.user_events.create!(
        event_name: "scheduled_workout_reminder_due",
        occurred_at: Time.current,
        metadata: {
          activation: {
            target_workout_at: zone.local(2026, 7, 20, 7, 30).iso8601
          }
        }
      )
      payload = valid_payload(
        event_id: event.id.to_s,
        campaign_key: "scheduled_workout_reminder_due",
        data: { "event_name" => "scheduled_workout_reminder_due" }
      )

      travel_to(zone.local(2026, 7, 20, 7, 0)) do
        with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(payload) }
      end

      expect(json["sent"]).to be(true)
      expect(PushDispatch.last.status).to eq("provider_accepted")
    end
  end

  # Regression suite for the user 529 incident. A scheduled workout reminder is
  # the consequence of a time the USER picked (07:00 workout, reminder 06:30),
  # so it obeys different timing rules from a campaign push:
  #
  #   6609 — redrived 39h late and still delivered  -> stale_scheduled_reminder
  #   7113 — deferred by quiet hours onto its own target -> may cross instead
  #   7604 — blocked by the cooldown 6609 consumed  -> exempt from cooldown/cap
  #
  # None of that waives consent: every guard below still applies.
  describe "scheduled workout reminder" do
    include ActiveSupport::Testing::TimeHelpers

    let!(:token) { create(:device_token, user: user, permission_status: "granted") }
    let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }
    let(:due_at) { zone.local(2026, 7, 20, 6, 30) }
    let(:target_at) { zone.local(2026, 7, 20, 7, 0) }

    before { user.update!(time_zone: "America/Sao_Paulo") }

    # The real shape produced by ScheduledWorkoutReminderEventEmitter: the event
    # is born at reminder time carrying both instants.
    def scheduled_event(activation: nil, payload_json: {}, occurred_at: due_at)
      activation ||= { reminder_due_at: due_at.iso8601, target_workout_at: target_at.iso8601 }
      user.user_events.create!(
        event_name: "scheduled_workout_reminder_due",
        occurred_at: occurred_at,
        metadata: { campaign: "first_workout_scheduled_reminder_v1", activation: activation },
        payload_json: payload_json
      )
    end

    # notification_type/route mirror config/communication_events.yml, and Make
    # echoes the numeric event_id back on the dispatch call.
    def scheduled_payload(event, overrides = {})
      valid_payload({
        event_id: event.id.to_s,
        notification_type: "activation_reminder",
        campaign_key: "scheduled_workout_reminder_due",
        route: "/workouts/ready",
        data: { "event_name" => "scheduled_workout_reminder_due" }
      }.merge(overrides))
    end

    def seed_delivered(dispatched_at:, user_event: nil, notification_type: "activation_reminder")
      PushDispatch.create!(
        user: user, user_event: user_event, notification_type: notification_type,
        status: "provider_accepted", idempotency_key: "seed:#{SecureRandom.hex(4)}",
        dispatched_at: dispatched_at
      )
    end

    def seed_delivered_scheduled(dispatched_at:)
      seed_delivered(dispatched_at: dispatched_at, user_event: scheduled_event(occurred_at: dispatched_at))
    end

    def dispatch_at(time, payload, quiet_hours: "true")
      travel_to(time) do
        with_env("PUSH_QUIET_HOURS_ENABLED" => quiet_hours) { post_dispatch(payload) }
      end
    end

    describe "quiet hours inside the explicit window" do
      # Event 7113: the user asked to train at 07:00 and the product warns at
      # 06:30. Deferring to 07:00 delivers a reminder for a workout that has
      # already started, so inside the window quiet hours step aside.
      it "delivers a 06:30 reminder for a 07:00 workout during quiet hours" do
        event = scheduled_event

        dispatch_at(due_at, scheduled_payload(event))

        expect(json).to include("status" => "provider_accepted", "sent" => true)
        expect(json["skip_reason"]).to be_nil
        expect(json["deferred"]).to be_nil.or be(false)
        dispatch = PushDispatch.last
        expect(dispatch.status).to eq("provider_accepted")
        expect(dispatch.skip_reason).to be_nil
      end

      it "still delivers on the last minute before the workout" do
        event = scheduled_event

        dispatch_at(target_at - 1.minute, scheduled_payload(event))

        expect(json["sent"]).to be(true)
      end

      # Before reminder_due_at there is no window yet, so nothing is waived and
      # the existing timing behaviour is preserved untouched.
      it "grants no quiet-hours exception before the reminder is due" do
        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
        event = scheduled_event

        dispatch_at(due_at - 30.minutes, scheduled_payload(event))

        expect(json["sent"]).to be(false)
        expect(json["status"]).to eq("skipped")
        expect(json["skip_reason"]).to eq("stale_after_quiet_hours")
      end

      it "leaves quiet hours in place for a non-scheduled push at the same hour" do
        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)

        dispatch_at(due_at, valid_payload)

        expect(json["status"]).to eq("deferred")
        expect(json["defer_reason"]).to eq("quiet_hours")
      end
    end

    describe "freshness gate" do
      # Event 6609: born 16/08 06:30, first delivery attempt stuck, redriven
      # 17/08 21:30 and delivered ~39h late. 21:30 is outside quiet hours, so
      # nothing but this gate stands between the redrive and FCM.
      it "skips a redrive attempted after the workout started" do
        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
        event = scheduled_event

        dispatch_at(target_at + 1.day + 14.hours + 30.minutes, scheduled_payload(event))

        expect(json).to include(
          "status" => "skipped", "skip_reason" => "stale_scheduled_reminder", "sent" => false
        )
        dispatch = PushDispatch.last
        expect(dispatch.status).to eq("skipped")
        expect(dispatch.skip_reason).to eq("stale_scheduled_reminder")
        expect(dispatch.dispatched_at).to be_nil
        expect(dispatch.provider_accepted_at).to be_nil
      end

      # What actually protects a real redrive is the correlation to the event,
      # not a string Make happens to send. Here campaign_key and data name
      # something else entirely and the gate must still hold.
      it "recognises the reminder through the UserEvent alone" do
        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
        event = scheduled_event
        payload = scheduled_payload(
          event, campaign_key: "generic_campaign_v1", data: { "workout_id" => "456" }
        )

        dispatch_at(target_at + 1.day, payload)

        dispatch = PushDispatch.last
        expect(dispatch.user_event_id).to eq(event.id)
        expect(dispatch.skip_reason).to eq("stale_scheduled_reminder")
        expect(dispatch.dispatched_at).to be_nil
      end

      it "skips exactly at the workout time" do
        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
        event = scheduled_event

        dispatch_at(target_at, scheduled_payload(event))

        expect(json["skip_reason"]).to eq("stale_scheduled_reminder")
      end

      # A 09:00 workout asked for at 06:00: still inside quiet hours and before
      # the 08:30 window, so it defers to 07:00 — legitimately, since 07:00 is
      # before the workout. If the release sweep then runs late, the row must
      # NOT be sent: by 10:00 the workout has already started.
      it "skips a deferred row whose release sweep ran after the workout time" do
        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
        event = scheduled_event(
          activation: {
            reminder_due_at: zone.local(2026, 7, 20, 8, 30).iso8601,
            target_workout_at: zone.local(2026, 7, 20, 9, 0).iso8601
          }
        )
        dispatch_at(zone.local(2026, 7, 20, 6, 0), scheduled_payload(event))
        expect(json["status"]).to eq("deferred")

        travel_to(zone.local(2026, 7, 20, 10, 0)) do
          stats = Make::PushDispatchRequest.dispatch_deferred(now: Time.current)
          expect(stats[:skipped]).to eq(1)
        end

        dispatch = PushDispatch.last
        expect(dispatch.status).to eq("skipped")
        expect(dispatch.skip_reason).to eq("stale_scheduled_reminder")
        expect(dispatch.dispatched_at).to be_nil
      end

      # No target means no basis to judge staleness. Nothing is invented and no
      # exception is granted: the conservative path stands.
      it "neither crashes nor waives anything when target_workout_at is missing" do
        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
        event = scheduled_event(activation: { reminder_due_at: due_at.iso8601 })

        dispatch_at(due_at, scheduled_payload(event))

        expect(response).to have_http_status(:ok)
        expect(json["sent"]).to be(false)
        expect(json["status"]).to eq("deferred")
        expect(json["skip_reason"]).to be_nil
      end

      it "ignores an unparseable target instead of blowing up" do
        event = scheduled_event(
          activation: { reminder_due_at: due_at.iso8601, target_workout_at: "not-a-time" }
        )

        dispatch_at(due_at, scheduled_payload(event), quiet_hours: "false")

        expect(response).to have_http_status(:ok)
        expect(json["sent"]).to be(true)
      end
    end

    # The schema-2 snapshot MakeWebhookClient persists is a canonical source in
    # its own right: if metadata is missing the instants but the snapshot has
    # them, the gates must NOT go blind and let a stale push through.
    describe "timestamps read from the persisted schema-2 payload" do
      def snapshot_event
        scheduled_event(
          activation: { reminder_number: 1 },
          payload_json: {
            "schema_version" => 2,
            "context" => {
              "activation" => {
                "reminder_due_at" => due_at.iso8601,
                "target_workout_at" => target_at.iso8601
              }
            }
          }
        )
      end

      it "recognises the delivery window" do
        dispatch_at(due_at, scheduled_payload(snapshot_event))

        expect(json["sent"]).to be(true)
      end

      it "recognises a stale redrive" do
        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)

        dispatch_at(target_at + 1.day + 14.hours, scheduled_payload(snapshot_event))

        expect(json["skip_reason"]).to eq("stale_scheduled_reminder")
      end

      it "falls back to the schema-1 metadata block in the snapshot" do
        expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
        event = scheduled_event(
          activation: { reminder_number: 1 },
          payload_json: {
            "schema_version" => 1,
            "metadata" => { "activation" => { "target_workout_at" => target_at.iso8601 } }
          }
        )

        dispatch_at(target_at + 1.day, scheduled_payload(event))

        expect(json["skip_reason"]).to eq("stale_scheduled_reminder")
      end
    end

    describe "engagement cooldown and weekly cap" do
      # Event 7604: the late delivery of 6609 at 21:30 consumed the 20h cooldown
      # and silenced the next morning's reminder.
      it "is not blocked by an engagement push delivered 9 hours earlier" do
        event = scheduled_event

        travel_to(due_at) do
          seed_delivered(dispatched_at: 9.hours.ago)
          with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(scheduled_payload(event)) }
        end

        expect(json["sent"]).to be(true)
        expect(json["skip_reason"]).to be_nil
      end

      # MAXIMUM_REMINDERS = 3 is the journey's own limit; the generic 2-per-7-days
      # cap would make the third reminder unreachable.
      it "delivers the third reminder of the journey" do
        event = scheduled_event

        travel_to(due_at) do
          seed_delivered_scheduled(dispatched_at: 2.days.ago)
          seed_delivered_scheduled(dispatched_at: 1.day.ago)
          with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(scheduled_payload(event)) }
        end

        expect(json["sent"]).to be(true)
        expect(ScheduledWorkoutReminderEligibility::MAXIMUM_REMINDERS).to eq(3)
      end

      it "does not spend another engagement push's cooldown" do
        travel_to(zone.local(2026, 7, 20, 10, 0)) do
          seed_delivered_scheduled(dispatched_at: 1.hour.ago)
          with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
        end

        expect(json["sent"]).to be(true)
      end

      it "does not spend another engagement push's weekly cap" do
        travel_to(zone.local(2026, 7, 20, 10, 0)) do
          seed_delivered_scheduled(dispatched_at: 2.days.ago)
          seed_delivered_scheduled(dispatched_at: 3.days.ago)
          with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
        end

        expect(json["sent"]).to be(true)
      end

      # The exemption is surgical: an ordinary engagement push delivered an hour
      # ago must still hold the cooldown for everybody else.
      it "keeps the cooldown for an ordinary engagement push" do
        travel_to(zone.local(2026, 7, 20, 10, 0)) do
          seed_delivered(dispatched_at: 1.hour.ago)
          with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
        end

        expect(json["skip_reason"]).to eq("cooldown_active")
      end

      it "keeps the weekly cap for an ordinary engagement push" do
        travel_to(zone.local(2026, 7, 20, 10, 0)) do
          seed_delivered(dispatched_at: 2.days.ago)
          seed_delivered(dispatched_at: 3.days.ago)
          with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
        end

        expect(json["skip_reason"]).to eq("frequency_capped")
      end

      # A legacy row cannot be classified after the fact, so it keeps counting
      # exactly as it does today. No migration, no historical guessing.
      it "keeps counting a delivered row with no correlated event" do
        travel_to(zone.local(2026, 7, 20, 10, 0)) do
          seed_delivered(dispatched_at: 1.hour.ago, user_event: nil)
          with_env("PUSH_QUIET_HOURS_ENABLED" => "true") { post_dispatch(valid_payload) }
        end

        expect(json["skip_reason"]).to eq("cooldown_active")
      end
    end

    # Timing is the ONLY thing this change relaxes. Every consent guard below is
    # evaluated with a reminder sitting inside its valid window.
    describe "consent guards are never waived" do
      def dispatch_in_window
        dispatch_at(due_at, scheduled_payload(scheduled_event))
      end

      it "skips no_preferences when the user never completed the consent flow" do
        user.notification_preferences&.destroy!
        user.reload

        dispatch_in_window

        expect(json["skip_reason"]).to eq("no_preferences")
      end

      it "skips global_opt_out when push is disabled" do
        user.notification_preferences!.update!(push_enabled: false)

        dispatch_in_window

        expect(json["skip_reason"]).to eq("global_opt_out")
      end

      it "skips global_opt_out when notifications were disabled" do
        user.notification_preferences!.update!(notifications_disabled_at: Time.current)

        dispatch_in_window

        expect(json["skip_reason"]).to eq("global_opt_out")
      end

      it "skips category_opt_out when workout reminders are off" do
        user.notification_preferences!.update!(workout_reminders_enabled: false)

        dispatch_in_window

        expect(json["skip_reason"]).to eq("category_opt_out")
      end

      it "skips no_active_token when no device is registered" do
        user.device_tokens.destroy_all

        dispatch_in_window

        expect(json["skip_reason"]).to eq("no_active_token")
      end

      it "skips permission_denied when the device refused notifications" do
        token.update!(permission_status: "denied")

        dispatch_in_window

        expect(json["skip_reason"]).to eq("permission_denied")
      end

      it "rejects an invalid payload" do
        dispatch_at(due_at, scheduled_payload(scheduled_event, title: ""))

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json["skip_reason"]).to eq("invalid_payload")
      end

      it "rejects an unauthenticated request" do
        event = scheduled_event
        travel_to(due_at) do
          with_env("PUSH_QUIET_HOURS_ENABLED" => "true") do
            post_dispatch(scheduled_payload(event), headers: auth_headers("wrong-token"))
          end
        end

        expect(response).to have_http_status(:unauthorized)
      end

      it "sends only once for the same event, campaign, user and type" do
        expect_any_instance_of(FirebasePushService).to receive(:deliver).once.and_return(
          FirebasePushService::Result.new(status: "sent", message_id: "mock/1", invalid_token: false)
        )
        event = scheduled_event
        payload = scheduled_payload(event)

        travel_to(due_at) do
          with_env("PUSH_QUIET_HOURS_ENABLED" => "true") do
            post_dispatch(payload)
            post_dispatch(payload)
          end
        end

        expect(json["status"]).to eq("duplicate")
        expect(PushDispatch.where(user_id: user.id).count).to eq(1)
      end
    end
  end

  describe "correlation with the business event" do
    let!(:token) { create(:device_token, user: user, permission_status: "granted") }

    let(:user_event) do
      UserEvent.create!(user: user, event_name: "user_inactive_3_days",
                        occurred_at: Time.current, metadata: {})
    end

    it "links the dispatch to the UserEvent Make echoed back" do
      post_dispatch(valid_payload(event_id: user_event.id.to_s))

      expect(PushDispatch.last.user_event_id).to eq(user_event.id)
    end

    # event_id is client-supplied. Attaching one user's dispatch to another
    # user's event would corrupt the whole pipeline view.
    it "refuses to correlate an event that belongs to somebody else" do
      other_event = UserEvent.create!(user: create(:user), event_name: "user_inactive_3_days",
                                      occurred_at: Time.current, metadata: {})

      post_dispatch(valid_payload(event_id: other_event.id.to_s))

      expect(PushDispatch.last.user_event_id).to be_nil
    end

    it "falls back to the legacy make-<id> correlation_id" do
      post_dispatch(valid_payload(event_id: "", correlation_id: "make-#{user_event.id}"))

      expect(PushDispatch.last.user_event_id).to eq(user_event.id)
    end

    it "leaves the link empty rather than guessing from campaign_key" do
      post_dispatch(valid_payload(event_id: "not-an-id"))

      dispatch = PushDispatch.last
      expect(dispatch.user_event_id).to be_nil
      expect(dispatch.campaign_key).to eq("workout_not_started_v1")
    end
  end

  def json
    JSON.parse(response.body)
  end
end

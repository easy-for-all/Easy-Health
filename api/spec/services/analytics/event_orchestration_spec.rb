require "rails_helper"

RSpec.describe Analytics::EventOrchestration do
  let(:user) { create(:user, marketing_consent: true) }

  # Signing a user up emits user_created / trial_started, and user_created IS an
  # orchestration event. Clearing them keeps each example's arithmetic about the
  # events it actually creates.
  before do
    user
    UserEvent.delete_all
  end

  def create_event(event_name, attrs = {})
    UserEvent.create!({
      user: user,
      event_name: event_name,
      occurred_at: Time.current,
      metadata: {}
    }.merge(attrs))
  end

  def create_dispatch(user_event: nil, status: "provider_accepted", skip_reason: nil, owner: user)
    PushDispatch.create!(
      user: owner,
      user_event: user_event,
      notification_type: "workout_reminder",
      idempotency_key: SecureRandom.hex(8),
      status: status,
      skip_reason: skip_reason
    )
  end

  describe "period handling" do
    it "defaults to 24h" do
      expect(described_class.new.call[:period][:key]).to eq("24h")
    end

    it "accepts the known periods" do
      %w[24h 7d 30d].each do |key|
        expect(described_class.new(period: key).call[:period][:key]).to eq(key)
      end
    end

    it "accepts a custom range" do
      result = described_class.new(start_date: "2026-08-01", end_date: "2026-08-10").call

      expect(result[:period][:key]).to eq("custom")
      expect(result[:period][:from]).to start_with("2026-08-01")
    end

    it "rejects an inverted range" do
      expect { described_class.new(start_date: "2026-08-10", end_date: "2026-08-01").call }
        .to raise_error(described_class::InvalidRange, /anterior/)
    end

    it "rejects an unparseable date" do
      expect { described_class.new(start_date: "ontem", end_date: "hoje").call }
        .to raise_error(described_class::InvalidRange)
    end

    it "excludes events outside the window" do
      old = create_event("user_inactive_3_days")
      old.update_column(:created_at, 40.days.ago)

      expect(described_class.new(period: "24h").call[:summary][:events_generated]).to eq(0)
    end
  end

  describe "the funnel" do
    it "counts generation, send, acceptance and failure" do
      create_event("user_inactive_3_days", make_delivery_status: "accepted_by_make", make_attempts_count: 1)
      create_event("user_inactive_7_days", make_delivery_status: "dead_letter", make_attempts_count: 5)
      create_event("first_workout_completed", make_delivery_status: "pending")

      summary = described_class.new.call[:summary]

      expect(summary[:events_generated]).to eq(3)
      expect(summary[:sent_to_make]).to eq(2)
      expect(summary[:accepted_by_make]).to eq(1)
      expect(summary[:failed_make]).to eq(1)
      expect(summary[:unique_users]).to eq(1)
    end

    # Historical rows filled the make_* columns inconsistently; counting on a
    # single one of them would under-report everything before this change.
    it "counts a legacy row that only has an accepted status" do
      create_event("user_inactive_3_days", make_delivery_status: "accepted_by_make",
                                           make_attempts_count: 0, make_first_attempt_at: nil)

      expect(described_class.new.call[:summary][:sent_to_make]).to eq(1)
    end

    it "counts a legacy row that only has a last_attempt_at" do
      create_event("user_inactive_3_days", make_delivery_status: "retrying",
                                           make_attempts_count: 0, make_last_attempt_at: 1.hour.ago)

      expect(described_class.new.call[:summary][:sent_to_make]).to eq(1)
    end

    it "reports rates as numerator/denominator, never a bare percentage" do
      create_event("user_inactive_3_days", make_delivery_status: "accepted_by_make", make_attempts_count: 1)
      create_event("user_inactive_7_days", make_delivery_status: "pending")

      rates = described_class.new.call[:summary][:rates]

      expect(rates[:generated_to_sent]).to eq({ numerator: 1, denominator: 2, value: 0.5 })
    end

    it "returns a nil rate instead of dividing by zero" do
      expect(described_class.new.call[:summary][:rates][:generated_to_sent][:value]).to be_nil
    end

    it "ignores events that are not orchestration events" do
      create_event("workout_started")

      expect(described_class.new.call[:summary][:events_generated]).to eq(0)
    end
  end

  # The panel used to read "182 generated / 33 accepted / 0 errors" while
  # activation_workout_created was being parked with event_not_orchestration,
  # because the denominator only ever contained catalogued events. Coverage
  # exists to make that denominator honest.
  describe "coverage" do
    it "separates expected, sent and not sent" do
      create_event("user_inactive_3_days", make_delivery_status: "accepted_by_make", make_attempts_count: 1)
      create_event("user_inactive_7_days", make_delivery_status: "disabled",
                                           make_last_error: "no_deliverable_channel")

      summary = described_class.new.call[:summary]

      expect(summary[:orchestration_expected]).to eq(2)
      expect(summary[:orchestration_sent]).to eq(1)
      expect(summary[:orchestration_not_sent]).to eq(1)
      expect(summary[:orchestration_coverage_pct]).to eq({ numerator: 1, denominator: 2, value: 0.5 })
    end

    it "counts every event produced, not only the catalogued ones" do
      create_event("user_inactive_3_days", make_delivery_status: "accepted_by_make", make_attempts_count: 1)
      create_event("push_sent")
      create_event("workout_started")

      summary = described_class.new.call[:summary]

      expect(summary[:all_events_generated]).to eq(3)
      expect(summary[:orchestration_expected]).to eq(1)
    end

    # The whole point of the second catalog: a push telemetry event must never
    # read as missing coverage.
    it "never counts an analytics-only event as a coverage failure" do
      create_event("push_sent")
      create_event("push_opened")

      summary = described_class.new.call[:summary]

      expect(summary[:analytics_only_events]).to eq(2)
      expect(summary[:orchestration_expected]).to eq(0)
      expect(summary[:orchestration_not_sent]).to eq(0)
      expect(summary[:uncatalogued_events]).to eq(0)
    end

    it "reports zero uncatalogued events while every registry event is classified" do
      expect(described_class.new.call[:summary][:uncatalogued_events]).to eq(0)
      expect(described_class.new.call[:catalog][:uncatalogued_events]).to be_empty
    end

    # Names produced by other subsystems are not this catalog's business; if the
    # scope were a `where.not` over arbitrary names they would raise a critical.
    it "ignores an event name that is not in the tracker's registry" do
      create_event("some_other_subsystem_event")

      summary = described_class.new.call[:summary]

      expect(summary[:uncatalogued_events]).to eq(0)
      expect(described_class.new.call[:warnings].map { |w| w[:code] }).not_to include("uncatalogued_event")
    end

    it "raises a critical warning when a registry event has no decision" do
      allow(CommunicationEvents).to receive(:uncatalogued_event_names).and_return(%w[workout_started])
      create_event("workout_started")

      warning = described_class.new.call[:warnings].find { |w| w[:code] == "uncatalogued_event" }

      expect(warning[:severity]).to eq("critical")
      expect(warning[:message]).to include("workout_started")
      expect(described_class.new.call[:summary][:uncatalogued_events]).to eq(1)
    end
  end

  # Grouped by cause, not by status: 'disabled' alone cannot tell an event
  # nobody catalogued apart from a user who withdrew email consent.
  describe "not_sent_breakdown" do
    it "separates causes that share the same delivery status" do
      allow(CommunicationEvents).to receive(:uncatalogued_event_names).and_return(%w[workout_started])
      create_event("workout_started", make_delivery_status: "disabled",
                                      make_last_error: "event_not_orchestration")
      create_event("user_inactive_3_days", make_delivery_status: "disabled",
                                           make_last_error: "no_deliverable_channel")

      breakdown = described_class.new.call[:not_sent_breakdown].index_by { |row| row[:reason] }

      expect(breakdown["event_not_orchestration"][:count]).to eq(1)
      expect(breakdown["event_not_orchestration"][:event_names]).to eq(%w[workout_started])
      expect(breakdown["no_deliverable_channel"][:count]).to eq(1)
    end

    it "falls back to the delivery status when no error explains it" do
      create_event("user_inactive_3_days", make_delivery_status: "pending")
      create_event("user_inactive_7_days", make_delivery_status: "disabled", make_last_error: nil)

      breakdown = described_class.new.call[:not_sent_breakdown].index_by { |row| row[:reason] }

      expect(breakdown["pending"][:count]).to eq(1)
      expect(breakdown["disabled_without_reason"][:count]).to eq(1)
    end

    it "excludes events that were sent and events classified as never-communication" do
      create_event("user_inactive_3_days", make_delivery_status: "accepted_by_make", make_attempts_count: 1)
      create_event("push_sent")

      expect(described_class.new.call[:not_sent_breakdown]).to be_empty
    end
  end

  describe "per event" do
    it "breaks the funnel down by event name with push results" do
      event = create_event("user_inactive_3_days", make_delivery_status: "accepted_by_make", make_attempts_count: 1)
      create_dispatch(user_event: event, status: "provider_accepted")
      create_dispatch(user_event: event, status: "skipped", skip_reason: "global_opt_out")

      row = described_class.new.call[:by_event].find { |r| r[:event_name] == "user_inactive_3_days" }

      expect(row[:generated]).to eq(1)
      expect(row[:accepted_by_make]).to eq(1)
      expect(row[:push_requested]).to eq(2)
      expect(row[:provider_accepted]).to eq(1)
      expect(row[:push_skipped]).to eq(1)
      expect(row[:candidate_channels]).to eq(%w[push])
      expect(row[:last_generated_at]).to be_present
    end

    # campaign_key belongs to the campaign and copy; Make can version it freely,
    # so joining on it would silently mis-attribute dispatches.
    it "correlates through the FK, not campaign_key" do
      event = create_event("user_inactive_3_days")
      dispatch = create_dispatch(user_event: event)
      dispatch.update!(campaign_key: "algo-totalmente-diferente-v9")

      row = described_class.new.call[:by_event].find { |r| r[:event_name] == "user_inactive_3_days" }

      expect(row[:push_requested]).to eq(1)
    end

    it "does not attribute an uncorrelated dispatch to any event" do
      create_event("user_inactive_3_days")
      create_dispatch(user_event: nil)

      result = described_class.new.call
      row = result[:by_event].find { |r| r[:event_name] == "user_inactive_3_days" }

      expect(row[:push_requested]).to eq(0)
      expect(result[:push_dispatch_results][:not_correlated]).to eq(1)
    end
  end

  describe "candidate channels" do
    # A push+email event is a candidate on BOTH channels. This measures intent,
    # not delivery — delivery lives in push_dispatch_results.
    it "counts a multichannel event once per channel" do
      create_event("user_inactive_7_days", make_delivery_status: "accepted_by_make", make_attempts_count: 1)

      channels = described_class.new.call[:candidate_channels].index_by { |c| c[:channel] }

      expect(channels["push"][:candidate_events]).to eq(1)
      expect(channels["email"][:candidate_events]).to eq(1)
      expect(channels["push"][:sent_to_make]).to eq(1)
    end

    it "lists whatsapp and in_app as known but unconfigured, with zero" do
      channels = described_class.new.call[:candidate_channels].index_by { |c| c[:channel] }

      expect(channels["whatsapp"][:candidate_events]).to eq(0)
      expect(channels["whatsapp"][:configured]).to be(false)
      expect(channels["in_app"][:configured]).to be(false)
      expect(channels["push"][:configured]).to be(true)
    end
  end

  describe "origin" do
    it "groups by origin surface and reports NULL as unknown" do
      create_event("user_inactive_3_days", origin_surface: "android")
      create_event("user_inactive_7_days", origin_surface: nil)

      origins = described_class.new.call[:by_origin].index_by { |o| o[:origin_surface] }

      expect(origins["android"][:events]).to eq(1)
      expect(origins["unknown"][:events]).to eq(1)
      expect(origins["backend_scheduler"][:events]).to eq(0)
    end

    it "always lists every known surface, so a zero is visible" do
      surfaces = described_class.new.call[:by_origin].map { |o| o[:origin_surface] }

      expect(surfaces).to match_array(RelationshipEventTracker::ORIGIN_SURFACES)
    end
  end

  describe "recent events" do
    it "shows the whole pipeline on one row" do
      event = create_event("user_inactive_3_days", make_delivery_status: "accepted_by_make",
                                                   make_attempts_count: 1, make_last_http_status: 200,
                                                   origin_surface: "backend_scheduler")
      create_dispatch(user_event: event, status: "skipped", skip_reason: "quiet_hours")

      row = described_class.new.call[:recent_events].first

      expect(row[:event_id]).to eq(event.id)
      expect(row[:origin_surface]).to eq("backend_scheduler")
      expect(row[:make_status]).to eq("accepted_by_make")
      expect(row[:make_http_status]).to eq(200)
      expect(row[:push_status]).to eq("skipped")
      expect(row[:skip_reason]).to eq("quiet_hours")
    end
  end

  describe "schedulers" do
    it "reports a never-registered scheduler instead of hiding it" do
      row = described_class.new.call[:schedulers].find { |s| s[:key] == "scheduled_workout_reminder" }

      expect(row[:registered]).to be(false)
    end

    it "surfaces the counters the job attached to its heartbeat" do
      Observability::Heartbeat.succeeded!("first_workout_not_started_2h",
                                          metadata: { candidates_found: 4, events_created: 2 })

      row = described_class.new.call[:schedulers].find { |s| s[:key] == "first_workout_not_started_2h" }

      expect(row[:registered]).to be(true)
      expect(row[:candidates_found]).to eq(4)
      expect(row[:events_created]).to eq(2)
      expect(row[:last_success_at]).to be_present
    end
  end

  describe "warnings" do
    def codes(result) = result[:warnings].map { |w| w[:code] }

    it "flags a never-registered scheduler" do
      expect(codes(described_class.new.call)).to include("heartbeat_missing")
    end

    it "flags a contract failure as critical" do
      create_event("first_workout_completed", make_delivery_status: "dead_letter",
                                              make_last_error: "missing_required_context")

      warning = described_class.new.call[:warnings].find { |w| w[:code] == "orchestration_event_dead_letter" }

      expect(warning[:severity]).to eq("critical")
    end

    it "flags push events generated with none accepted by Make" do
      create_event("user_inactive_3_days")

      expect(codes(described_class.new.call)).to include("zero_push_to_make")
    end

    it "does not flag zero push when Make accepted them" do
      create_event("user_inactive_3_days", make_delivery_status: "accepted_by_make", make_attempts_count: 1)

      expect(codes(described_class.new.call)).not_to include("zero_push_to_make")
    end

    it "flags dispatches requested with none accepted by the provider" do
      event = create_event("user_inactive_3_days", make_delivery_status: "accepted_by_make", make_attempts_count: 1)
      create_dispatch(user_event: event, status: "failed")

      expect(codes(described_class.new.call)).to include("zero_provider_accepted")
    end

    it "flags an env-only event as catalog drift" do
      with_env("MAKE_WEBHOOK_ALLOWED_EVENTS" => "workout_started") do
        expect(codes(described_class.new.call)).to include("allowlist_drift")
      end
    end

    # "disabled" is normal when the webhook is off or the reason is known.
    # Anything else is an orchestration event that was born and silently parked.
    it "flags an unexplained disabled event" do
      with_env("MAKE_WEBHOOK_ENABLED" => "true", "MAKE_WEBHOOK_URL" => "https://make.example",
               "MAKE_WEBHOOK_SECRET" => "s") do
        create_event("user_inactive_3_days", make_delivery_status: "disabled", make_last_error: nil)

        expect(codes(described_class.new.call)).to include("orchestration_event_disabled")
      end
    end

    it "does not flag a disabled event with a known reason" do
      with_env("MAKE_WEBHOOK_ENABLED" => "true", "MAKE_WEBHOOK_URL" => "https://make.example",
               "MAKE_WEBHOOK_SECRET" => "s") do
        create_event("user_inactive_3_days", make_delivery_status: "disabled",
                                             make_last_error: "no_deliverable_channel")

        expect(codes(described_class.new.call)).not_to include("orchestration_event_disabled")
      end
    end

    it "does not flag disabled events while the webhook is globally off" do
      with_env("MAKE_WEBHOOK_ENABLED" => "false") do
        create_event("user_inactive_3_days", make_delivery_status: "disabled", make_last_error: nil)

        expect(codes(described_class.new.call)).not_to include("orchestration_event_disabled")
      end
    end
  end
end

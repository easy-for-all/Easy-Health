require "rails_helper"

# product_analytics_events never carried an installation_id, on any path: the
# client payload had no such field, the ingestion never read the header, and
# Observability::Context deliberately withheld it from event properties. The
# consequence in production was that an anonymous Android install could only be
# tied to its events by hand, by comparing timestamps.
#
# It lives in `properties` on purpose — no column, no migration.
RSpec.describe "installation_id correlation" do
  let(:installation_id) { "inst-corr-#{SecureRandom.uuid}" }

  def event(overrides = {})
    {
      event_name: "app_first_open",
      event_version: 1,
      occurred_at: Time.current.iso8601,
      anonymous_id: "anon-1",
      session_id: "sess-1",
      platform: "android",
      app_surface: "native_shell",
      environment: "test",
      properties: {}
    }.merge(overrides)
  end

  describe "Analytics::Ingestion" do
    it "keeps the installation_id the client sent in the body" do
      Analytics::Ingestion.new(
        user: nil,
        events: [ event(properties: { "installation_id" => installation_id }) ]
      ).call

      expect(ProductAnalyticsEvent.last.properties["installation_id"]).to eq(installation_id)
    end

    it "falls back to the request context when the body omits it" do
      Observability::Context.installation_id = installation_id

      Analytics::Ingestion.new(user: nil, events: [ event ]).call

      expect(ProductAnalyticsEvent.last.properties["installation_id"]).to eq(installation_id)
    ensure
      Observability::Context.reset
    end

    it "never lets the header override what the client actually reported" do
      # sendBeacon carries the body but no headers, so the two can legitimately
      # disagree; the body is the one that describes the event.
      Observability::Context.installation_id = "inst-from-header"

      Analytics::Ingestion.new(
        user: nil,
        events: [ event(properties: { "installation_id" => installation_id }) ]
      ).call

      expect(ProductAnalyticsEvent.last.properties["installation_id"]).to eq(installation_id)
    ensure
      Observability::Context.reset
    end

    it "stores no installation_id when neither source has one" do
      Analytics::Ingestion.new(user: nil, events: [ event ]).call

      expect(ProductAnalyticsEvent.last.properties).not_to have_key("installation_id")
    end

    it "does not strip it as a sensitive key" do
      # installation_id must not match SENSITIVE_KEY_PATTERN in the shared
      # sanitizer, or this whole mechanism silently does nothing.
      cleaned = RelationshipEventTracker.sanitize_metadata("installation_id" => installation_id)

      expect(cleaned["installation_id"]).to eq(installation_id)
    end

    it "keeps anonymous_id and session_id as their own dimensions" do
      Analytics::Ingestion.new(
        user: nil,
        events: [ event(properties: { "installation_id" => installation_id }) ]
      ).call

      row = ProductAnalyticsEvent.last
      expect(row.anonymous_id).to eq("anon-1")
      expect(row.session_id).to eq("sess-1")
    end
  end

  describe "Observability::Context.to_event_properties" do
    it "carries the raw installation_id so server events join the same timeline" do
      Observability::Context.installation_id = installation_id
      Observability::Context.platform = "android"

      expect(Observability::Context.to_event_properties[:installation_id]).to eq(installation_id)
    ensure
      Observability::Context.reset
    end

    it "omits it entirely when the request carried none" do
      Observability::Context.platform = "android"

      expect(Observability::Context.to_event_properties).not_to have_key(:installation_id)
    ensure
      Observability::Context.reset
    end

    it "keeps sending only the hashed ref to external sinks" do
      Observability::Context.installation_id = installation_id

      tags = Observability::Context.sentry_tags
      expect(tags[:installation_ref]).to be_present
      expect(tags.values.map(&:to_s)).not_to include(installation_id)
    ensure
      Observability::Context.reset
    end

    it "lands on a server-recorded event, joinable to app_installations" do
      installation = create(:app_installation, installation_id: installation_id, platform: "android")
      Observability::Context.installation_id = installation_id

      Observability::Events.google_auth_started(flow: "native", intent: "sign_up")

      row = ProductAnalyticsEvent.find_by(event_name: "google_auth_started")
      expect(row.properties["installation_id"]).to eq(installation.installation_id)
    ensure
      Observability::Context.reset
    end
  end
end

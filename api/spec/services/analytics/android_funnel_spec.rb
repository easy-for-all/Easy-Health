require "rails_helper"

RSpec.describe Analytics::AndroidFunnel do
  # The funnel only exists for instrumented builds; everything below uses one
  # above the threshold unless a test is specifically about the cut.
  INSTRUMENTED_BUILD = "51".freeze

  def install(build: INSTRUMENTED_BUILD, user: nil, **attrs)
    create(:app_installation, app_build: build, user: user, **attrs)
  end

  def emit(installation, event_name, at: 1.hour.ago, user: nil)
    create(
      :product_analytics_event,
      event_name: event_name,
      occurred_at: at,
      user: user,
      installation_id: installation.installation_id
    )
  end

  def steps_by_key(payload)
    payload[:steps].index_by { |step| step[:key] }
  end

  def bucket_count(payload, key)
    payload[:stage_buckets].find { |bucket| bucket[:key] == key }[:count]
  end

  describe "taxonomy" do
    it "only uses event names that exist in the catalog" do
      unknown = described_class::FUNNEL_EVENTS - Analytics::EventCatalog.names

      expect(unknown).to be_empty,
                         "not in config/analytics/events.yml: #{unknown.join(", ")}"
    end

    it "places session_started between first open and landing" do
      keys = described_class::STAGES.map { |stage| stage[:key] }

      expect(keys.index("session_started")).to eq(keys.index("first_open") + 1)
      expect(keys.index("landing")).to eq(keys.index("session_started") + 1)
    end

    it "places auth_provider_clicked between auth choice and auth started" do
      keys = described_class::STAGES.map { |stage| stage[:key] }

      expect(keys.index("auth_provider")).to eq(keys.index("auth_choice") + 1)
      expect(keys.index("auth_client")).to eq(keys.index("auth_provider") + 1)
    end
  end

  describe "counting unit" do
    it "counts distinct installations, never raw events" do
      2.times { install }
      AppInstallation.find_each { |record| emit(record, "app_first_open") }

      payload = described_class.new.call

      expect(payload[:cohort][:installations]).to eq(2)
      expect(steps_by_key(payload)["first_open"][:count]).to eq(2)
    end

    it "does not inflate a step when the same installation repeats an event" do
      record = install
      5.times { |i| emit(record, "app_first_open", at: i.hours.ago) }
      4.times { |i| emit(record, "session_started", at: i.hours.ago) }

      payload = described_class.new.call

      expect(steps_by_key(payload)["first_open"][:count]).to eq(1)
      expect(steps_by_key(payload)["session_started"][:count]).to eq(1)
    end
  end

  describe "audience classification" do
    it "keeps Google Test Lab out of the external funnel" do
      robot = create(:user, email: "robot@cloudtestlabaccounts.com")
      record = install(user: robot)
      emit(record, "app_first_open")

      expect(described_class.new.call[:cohort][:installations]).to eq(0)
      expect(described_class.new(audience: "all").call[:cohort][:installations]).to eq(1)
    end

    it "keeps a known internal account out of the external funnel" do
      internal = create(:user, email: "mail.marcus.reis@gmail.com")
      record = install(user: internal)
      emit(record, "app_first_open")

      expect(described_class.new.call[:cohort][:installations]).to eq(0)
      expect(described_class.new(audience: "internal_test").call[:cohort][:installations]).to eq(1)
    end

    it "excludes an anonymous installation when an event proves Test Lab drove it" do
      robot = create(:user, email: "robot@cloudtestlabaccounts.com")
      record = install
      emit(record, "app_first_open", user: robot)

      expect(described_class.new.call[:cohort][:installations]).to eq(0)
    end

    it "counts an anonymous installation with no evidence as external" do
      record = install
      emit(record, "app_first_open")

      expect(described_class.new.call[:cohort][:installations]).to eq(1)
    end

    it "includes internal and test accounts under the 'all' filter" do
      emit(install(user: create(:user, email: "robot@cloudtestlabaccounts.com")), "app_first_open")
      emit(install(user: create(:user, email: "hello@easyhealth.art")), "app_first_open")
      emit(install, "app_first_open")

      expect(described_class.new(audience: "all").call[:cohort][:installations]).to eq(3)
    end
  end

  describe "stage buckets" do
    it "classifies an installation that stopped after first open" do
      emit(install, "app_first_open")

      expect(bucket_count(described_class.new.call, "stopped_first_open")).to eq(1)
    end

    it "classifies an installation that started a session and never saw the landing" do
      record = install
      emit(record, "app_first_open")
      emit(record, "session_started")

      payload = described_class.new.call

      expect(bucket_count(payload, "stopped_session_started")).to eq(1)
      expect(bucket_count(payload, "stopped_first_open")).to eq(0)
    end

    it "classifies an installation that stopped after the landing" do
      record = install
      %w[app_first_open session_started landing_page_viewed].each { |name| emit(record, name) }

      expect(bucket_count(described_class.new.call, "stopped_landing")).to eq(1)
    end

    it "classifies an installation that saw auth and chose nothing" do
      record = install
      %w[app_first_open session_started landing_page_viewed auth_screen_viewed]
        .each { |name| emit(record, name) }

      expect(bucket_count(described_class.new.call, "stopped_auth_screen")).to eq(1)
    end

    it "classifies an installation that chose signup and never started it" do
      record = install
      %w[landing_page_viewed auth_screen_viewed signup_selected].each { |name| emit(record, name) }

      expect(bucket_count(described_class.new.call, "stopped_auth_choice")).to eq(1)
    end

    it "classifies an installation that clicked auth and never started it" do
      record = install
      %w[auth_screen_viewed signup_selected auth_provider_clicked].each { |name| emit(record, name) }

      expect(bucket_count(described_class.new.call, "stopped_auth_provider")).to eq(1)
    end

    it "classifies an installation that started auth on the client and never reached the API" do
      record = install
      %w[auth_screen_viewed signup_selected auth_provider_clicked social_login_started].each { |name| emit(record, name) }

      expect(bucket_count(described_class.new.call, "stopped_auth_client")).to eq(1)
    end

    it "classifies an installation that reached the API and did not complete" do
      record = install
      %w[signup_selected auth_provider_clicked social_login_started google_auth_started].each { |name| emit(record, name) }

      expect(bucket_count(described_class.new.call, "stopped_auth_api")).to eq(1)
    end

    it "classifies an installation with no funnel event at all" do
      install

      expect(bucket_count(described_class.new.call, "no_events")).to eq(1)
    end

    it "reaches the end of the funnel when auth completed and the link succeeded" do
      user = create(:user, email: "externo@example.com", signup_source: "android")
      record = install(user: user)
      %w[app_first_open session_started landing_page_viewed auth_screen_viewed signup_selected
         auth_provider_clicked social_login_started google_auth_started google_auth_succeeded
         installation_link_succeeded].each { |name| emit(record, name) }

      payload = described_class.new.call

      expect(bucket_count(payload, "completed")).to eq(1)
      expect(steps_by_key(payload)["linked"][:count]).to eq(1)
    end

    it "counts a legacy linked installation as linked even without the link event" do
      record = install(user: create(:user, email: "legado@example.com"))
      emit(record, "google_auth_succeeded")

      expect(steps_by_key(described_class.new.call)["linked"][:count]).to eq(1)
    end
  end

  describe "user created without a link (conflict)" do
    # The device already belongs to account A; account B signs up on it and the
    # link fails with user_conflict. B authenticated and exists — the device did
    # not become B's.
    let!(:owner) { create(:user, email: "dono@example.com") }
    let!(:record) do
      install(user: owner, last_link_failure_code: "user_conflict", link_attempts_count: 2)
    end

    before do
      create(:user, email: "easyhealthmr3@gmail.com", signup_source: "android")
      %w[auth_screen_viewed signup_selected auth_provider_clicked social_login_started
         android_registration_started android_registration_succeeded].each { |name| emit(record, name) }
    end

    it "counts the completed auth and the created user but not the link" do
      payload = described_class.new.call
      steps = steps_by_key(payload)

      expect(steps["auth_done"][:count]).to eq(1)
      expect(steps["android_users"][:count]).to eq(1)
      expect(steps["android_users"][:unit]).to eq("users")
      expect(steps["linked"][:count]).to eq(0)
    end

    it "classifies it as authenticated but not linked" do
      expect(bucket_count(described_class.new.call, "stopped_auth_done")).to eq(1)
      expect(bucket_count(described_class.new.call, "completed")).to eq(0)
    end

    it "exposes the conflict in the investigation list" do
      row = described_class.new.installations(stage: "stopped_auth_done")[:installations].first

      expect(row[:link_result]).to eq("conflict")
      expect(row[:last_link_failure_code]).to eq("user_conflict")
      expect(row[:linked]).to be(false)
    end

    it "reports the failure code separately from the other codes" do
      other = install
      other.update_columns(last_link_failure_code: "installation_not_found")

      expect(described_class.new.call[:link_failures])
        .to eq("user_conflict" => 1, "installation_not_found" => 1)
    end
  end

  describe "build scope" do
    it "leaves builds below the instrumentation threshold out by default" do
      emit(install(build: "50"), "app_first_open")
      emit(install(build: "51"), "app_first_open")

      expect(described_class.new.call[:cohort][:installations]).to eq(1)
    end

    it "reports installations excluded for a missing or invalid build" do
      install(build: nil)
      install(build: "nightly")
      install(build: "51")

      payload = described_class.new.call

      expect(payload[:cohort][:installations]).to eq(1)
      expect(payload[:cohort][:excluded][:missing_or_invalid_build]).to eq(2)
    end

    it "filters by an exact build when asked" do
      emit(install(build: "51"), "app_first_open")
      emit(install(build: "53"), "app_first_open")

      payload = described_class.new(build: "53").call

      expect(payload[:cohort][:installations]).to eq(1)
      expect(payload[:available_builds]).to eq([ 53, 51 ])
    end

    it "honours ANDROID_FUNNEL_MIN_BUILD and ignores a malformed value" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANDROID_FUNNEL_MIN_BUILD").and_return("60")
      expect(described_class.min_instrumented_build).to eq(60)

      allow(ENV).to receive(:[]).with("ANDROID_FUNNEL_MIN_BUILD").and_return("nope")
      expect(described_class.min_instrumented_build).to eq(described_class::DEFAULT_MIN_INSTRUMENTED_BUILD)
    end
  end

  describe "conversions" do
    it "reports each step against the previous one and against the cohort" do
      4.times { |i| emit(install, "app_first_open", at: i.minutes.ago) }
      AppInstallation.limit(2).each { |record| emit(record, "session_started") }

      steps = steps_by_key(described_class.new.call)

      expect(steps["first_open"][:conversion_from_previous][:value]).to eq(100.0)
      expect(steps["session_started"][:conversion_from_previous][:value]).to eq(50.0)
      expect(steps["session_started"][:conversion_from_cohort][:value]).to eq(50.0)
    end

    it "does not break when the denominator is zero" do
      payload = described_class.new.call
      steps = steps_by_key(payload)

      expect(payload[:cohort][:installations]).to eq(0)
      expect(steps["first_open"][:conversion_from_previous][:status]).to eq("no_coverage")
      expect(steps["first_open"][:conversion_from_previous][:value]).to eq(0.0)
      expect(payload[:biggest_drop]).to be_nil
    end
  end

  describe "biggest drop" do
    it "points at the consecutive pair with the largest absolute loss" do
      10.times { |i| emit(install, "app_first_open", at: i.minutes.ago) }
      AppInstallation.limit(9).each do |record|
        emit(record, "session_started")
        emit(record, "landing_page_viewed")
      end
      AppInstallation.limit(2).each { |record| emit(record, "auth_screen_viewed") }

      drop = described_class.new.call[:biggest_drop]

      expect(drop[:from_key]).to eq("landing")
      expect(drop[:to_key]).to eq("auth_screen")
      expect(drop[:lost]).to eq(7)
      expect(drop[:drop_rate][:value]).to eq(77.8)
    end

    it "considers the pairs introduced by session_started" do
      10.times { |i| emit(install, "app_first_open", at: i.minutes.ago) }
      AppInstallation.limit(1).each do |record|
        emit(record, "session_started")
        emit(record, "landing_page_viewed")
      end

      drop = described_class.new.call[:biggest_drop]

      expect([ drop[:from_key], drop[:to_key] ]).to eq(%w[first_open session_started])
      expect(drop[:lost]).to eq(9)
    end
  end

  describe "#installations" do
    it "returns operational fields only and never a raw properties blob" do
      record = install(
        app_version: "1.0.51",
        device_manufacturer: "samsung",
        device_model: "SM-A155M",
        operating_system: "android",
        operating_system_version: "14"
      )
      emit(record, "app_first_open")
      emit(record, "session_started", at: 1.minute.ago)

      row = described_class.new.installations(stage: "stopped_session_started")[:installations].first

      expect(row[:installation_id]).to eq(record.installation_id)
      expect(row[:app_build]).to eq(INSTRUMENTED_BUILD)
      expect(row[:device_manufacturer]).to eq("samsung")
      expect(row[:last_stage]).to eq("stopped_session_started")
      expect(row[:last_event_name]).to eq("session_started")
      expect(row[:user_id]).to be_nil
      expect(row[:email]).to be_nil
      expect(row.keys).not_to include(:properties)
    end

    it "paginates and rejects an unknown stage" do
      3.times { |i| emit(install, "app_first_open", at: i.minutes.ago) }

      page = described_class.new.installations(stage: "stopped_first_open", page: 2, per: 2)
      expect(page[:total]).to eq(3)
      expect(page[:installations].size).to eq(1)

      expect(described_class.new.installations(stage: "made_up")[:installations]).to eq([])
    end
  end

  describe "period filter" do
    it "restricts the cohort to the selected window" do
      old = install
      old.update_columns(created_at: 40.days.ago)
      emit(old, "app_first_open", at: 40.days.ago)
      emit(install, "app_first_open")

      expect(described_class.new(period: "7d").call[:cohort][:installations]).to eq(1)
      expect(described_class.new(period: "since_instrumentation").call[:cohort][:installations]).to eq(2)
    end

    it "falls back to the default period and audience for unknown values" do
      service = described_class.new(period: "last_century", audience: "friends")

      expect(service.period).to eq("since_instrumentation")
      expect(service.audience).to eq("external")
    end
  end
end

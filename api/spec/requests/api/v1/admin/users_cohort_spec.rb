require "rails_helper"

# The cohort view on GET /api/v1/admin/users: filter accounts by the REAL date
# the account was created and by where it was created FROM, plus the Android
# diagnostic funnel over the same window.
RSpec.describe "Api::V1::Admin::Users cohort view", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # Monday 12:00 in São Paulo.
  around { |example| travel_to(Time.utc(2026, 7, 27, 15, 0)) { example.run } }

  let(:sp) { ActiveSupport::TimeZone["America/Sao_Paulo"] }
  let(:admin) { create(:user, :admin, created_at: sp.parse("2026-01-01 10:00")) }

  # Devise's integration sign_in authenticates only the NEXT request (it goes
  # through Warden.on_next_request), and this API has no HTML session route to
  # fall back on, so a second request in the same example redirects instead of
  # answering. Re-authenticating per request keeps multi-request examples
  # measuring what they claim to measure instead of passing on a 302.
  def get_users(params = {})
    sign_in admin
    get "/api/v1/admin/users", params: params
    expect(response).to have_http_status(:ok), "expected 200, got #{response.status}"
    response.parsed_body
  end

  it "forbids non-admins" do
    sign_in create(:user)
    get "/api/v1/admin/users"

    expect(response).to have_http_status(:forbidden).or have_http_status(:unauthorized)
  end

  context "as an admin" do
    it "defaults to the since-Monday window and publishes the resolved boundaries" do
      body = get_users

      expect(body["definitions"]["period"]).to eq("since_monday")
      expect(body["definitions"]["timezone"]).to eq("America/Sao_Paulo")
      expect(body["definitions"]["window_from"]).to eq("2026-07-27T00:00:00-03:00")
    end

    it "lists a web account created today under Hoje + Web" do
      create(:user, created_at: sp.parse("2026-07-27 09:00"), signup_source: "web")

      body = get_users(period: "today", source: "web")

      expect(body["users"].map { |u| u["signup_source"] }).to eq([ "web" ])
      expect(body["summary"]["by_source"]["web"]).to eq(1)
    end

    it "lists an Android account created today under Hoje + Android" do
      create(:user, created_at: sp.parse("2026-07-27 09:00"), signup_source: "android")

      body = get_users(period: "today", source: "android")

      expect(body["users"].map { |u| u["signup_source"] }).to eq([ "android" ])
      expect(body["android_funnel"]["users_created_from_android"]).to eq(1)
    end

    it "excludes an account created Sunday from the since-Monday window" do
      create(:user, created_at: sp.parse("2026-07-26 23:30"), signup_source: "web", name: "Sunday User")

      body = get_users(period: "since_monday")

      expect(body["total"]).to eq(0)
      expect(body["users"]).to be_empty
    end

    it "includes an account created Monday 00:01 São Paulo" do
      create(:user, created_at: sp.parse("2026-07-27 00:01"), signup_source: "web")

      expect(get_users(period: "since_monday")["total"]).to eq(1)
    end

    it "shows an account with no recorded origin as unknown" do
      create(:user, created_at: sp.parse("2026-07-27 09:00"))

      body = get_users(period: "since_monday")

      expect(body["users"].first["signup_source"]).to eq("unknown")
      expect(body["summary"]["by_source"]["unknown"]).to eq(1)
    end

    it "orders by created_at DESC" do
      create(:user, created_at: sp.parse("2026-07-27 09:00"), email: "older@example.com")
      create(:user, created_at: sp.parse("2026-07-27 11:00"), email: "newer@example.com")

      created = get_users(period: "since_monday")["users"].map { |u| u["created_at"] }

      expect(created).to eq(created.sort.reverse)
    end

    describe "Android installation columns" do
      let!(:user) { create(:user, created_at: sp.parse("2026-07-27 09:00"), signup_source: "android") }
      let!(:install) do
        create(:app_installation, user: user, installation_id: "a82f1234567890abc91c",
                                  app_version: "1.0.49", app_build: "49",
                                  first_seen_at: sp.parse("2026-07-27 08:00"),
                                  last_seen_at: sp.parse("2026-07-27 09:00"))
      end

      it "exposes the abbreviated id, version and build" do
        row = get_users(period: "since_monday")["users"].first

        expect(row["installation_id_short"]).to eq("a82f...91c")
        expect(row["app_version"]).to eq("1.0.49")
        expect(row["app_build"]).to eq("49")
      end

      it "never leaks the full installation_id" do
        get_users(period: "since_monday")

        expect(response.body).not_to include(install.installation_id)
      end

      it "carries a log-correlatable fingerprint instead" do
        row = get_users(period: "since_monday")["users"].first

        expect(row["installation_fingerprint"]).to eq(Digest::SHA256.hexdigest(install.installation_id)[0, 12])
      end

      it "renders nothing for a user with no Android installation" do
        create(:user, created_at: sp.parse("2026-07-27 10:00"), signup_source: "web", email: "webonly@example.com")

        row = get_users(period: "since_monday", source: "web")["users"].first

        expect(row["installation_id_short"]).to be_nil
        expect(row["app_version"]).to be_nil
      end
    end

    describe "input handling" do
      it "falls back to the default period instead of erroring on junk" do
        body = get_users(period: "lol'; DROP TABLE users--", source: "windowsphone")

        expect(body["definitions"]["period"]).to eq("since_monday")
        expect(body["definitions"]["source"]).to be_nil
      end
    end

    # Regression, pre-dating the cohort view: the session-count filters used
    # GROUP BY users.id on a relation that also eager-loads subscription, so
    # Postgres rejected the SELECT ("subscriptions_users.id must appear in the
    # GROUP BY clause") and the endpoint 500'd whenever the filter matched. The
    # same GROUP BY also made .count return a Hash, which the frontend turned into
    # Math.ceil(Hash / per) = NaN and lost pagination.
    describe "session-count filters" do
      def user_with_sessions(count, email:)
        user = create(:user, created_at: sp.parse("2026-07-27 09:00"), signup_source: "android", email: email)
        WorkoutPlan.create!(user: user, active: true)
        count.times do
          WorkoutSession.create!(user: user, status: "completed",
                                 completed_at: sp.parse("2026-07-27 10:00"), duration_minutes: 30)
        end
        user
      end

      it "returns matching users and an Integer total for 1_session" do
        user_with_sessions(1, email: "one@example.com")
        user_with_sessions(3, email: "three@example.com")

        body = get_users(period: "since_monday", filter: "1_session")

        expect(body["total"]).to be_a(Integer).and eq(1)
        expect(body["users"].length).to eq(1)
      end

      it "returns matching users for 3plus_sessions" do
        user_with_sessions(1, email: "one@example.com")
        user_with_sessions(3, email: "three@example.com")

        body = get_users(period: "since_monday", filter: "3plus_sessions")

        expect(body["total"]).to eq(1)
      end

      it "does not 500 on the engagement filters either" do
        user_with_sessions(2, email: "two@example.com")

        %w[engagement_high engagement_medium engagement_low].each do |filter|
          body = get_users(period: "since_monday", filter: filter)

          expect(body["total"]).to be_a(Integer)
        end
      end
    end

    it "is read-only: filtering changes no record and emits no event" do
      admin # created up front, so the lazy let does not count as a change below
      user = create(:user, created_at: sp.parse("2026-07-27 09:00"), signup_source: "android")
      install = create(:app_installation, user: user,
                                          first_seen_at: sp.parse("2026-07-27 08:00"),
                                          last_seen_at: sp.parse("2026-07-27 09:00"))

      expect {
        get_users(period: "since_monday", source: "android")
        get_users(period: "30d")
        get_users(period: "all")
      }.not_to change {
        [
          user.reload.updated_at, user.signup_source,
          install.reload.updated_at, install.user_id,
          User.count, AppInstallation.count, ProductAnalyticsEvent.count, UserEvent.count
        ]
      }
    end
  end
end

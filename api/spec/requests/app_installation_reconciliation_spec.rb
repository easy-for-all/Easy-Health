require "rails_helper"

# Marco 1/3: every authenticated request carrying X-Installation-Id records the
# request signal first, then delegates the user link to AppInstallations::LinkToUser.
RSpec.describe "AppInstallation reconciliation", type: :request do
  include ActiveSupport::Testing::TimeHelpers

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

    it "associates it to the current user and stamps the request/link signals" do
      sign_in user
      authenticated_request(header)

      expect(response).to have_http_status(:ok)
      installation.reload
      expect(installation.user_id).to eq(user.id)
      expect(installation.first_authenticated_request_at).to be_present
      expect(installation.first_link_attempt_at).to be_present
      expect(installation.linked_at).to be_present
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
      create(:app_installation, user: user, last_authenticated_at: 3.hours.ago,
                                first_authenticated_request_at: 3.hours.ago, linked_at: 3.hours.ago)
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
      installation.update_columns(last_authenticated_at: 5.minutes.ago,
                                  first_authenticated_request_at: 5.minutes.ago,
                                  linked_at: 5.minutes.ago)
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
      create(:app_installation, user: owner, last_authenticated_at: 3.hours.ago,
                                first_authenticated_request_at: 3.hours.ago, linked_at: 3.hours.ago)
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
      expect(installation.last_link_failure_code).to eq("user_conflict")
      expect(Rails.logger).to have_received(:warn).with(/installation_link_conflict/)
    end

    # The bug this suite exists to prevent: reconciliation is an after_action on
    # every authenticated request, so an unresolvable conflict wrote one
    # ProductAnalyticsEvent per API call the app made — dozens per session.
    describe "repeated requests on the same unresolvable conflict" do
      def link_failures
        ProductAnalyticsEvent.where(event_name: "installation_link_failed")
      end

      # The session does not survive from one request to the next in this suite,
      # and an unauthenticated request skips reconciliation entirely — which
      # would make every "no new write / no new event" assertion below a false
      # green. So each call signs in again and the status is asserted, proving
      # the reconciliation really ran N times.
      def authenticated_requests(count, as: user, headers: header)
        count.times do
          sign_in as
          authenticated_request(headers)
          expect(response).to have_http_status(:ok)
        end
      end

      it "records exactly ONE representative event for the whole day" do
        expect { authenticated_requests(8) }.to change { link_failures.count }.by(1)

        expect(link_failures.last.properties["link_result"]).to eq("conflict")
      end

      it "stops writing to the installation after the first conflict" do
        authenticated_requests(1)
        before_attrs = installation.reload.attributes

        authenticated_requests(5)

        expect(installation.reload.attributes).to eq(before_attrs)
      end

      it "records the conflict again the next day, so it stays visible" do
        authenticated_requests(4)

        travel_to(1.day.from_now) do
          expect { authenticated_requests(1) }.to change { link_failures.count }.by(1)
        end
      end

      # The dedup window is a day in the REPORTING zone (America/Sao_Paulo), the
      # same cut every other daily figure uses. Keyed on UTC by accident, a
      # conflict at 22h local would open a new bucket mid-evening.
      it "keeps one bucket across the UTC midnight of the same local evening" do
        travel_to(Time.utc(2026, 8, 1, 23, 30)) do # 20:30 in São Paulo
          expect { authenticated_requests(1) }.to change { link_failures.count }.by(1)
        end

        travel_to(Time.utc(2026, 8, 2, 1, 30)) do # still 22:30 the SAME local day
          expect { authenticated_requests(1) }.not_to change { link_failures.count }
        end
      end

      it "gives a different user its own representative event" do
        authenticated_requests(4)

        expect { authenticated_requests(1, as: create(:user)) }
          .to change { link_failures.count }.by(1)
      end
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

    # not_found stays RETRYABLE — a later register really can create the row —
    # but it repeats on every request exactly like a conflict does, so the event
    # is throttled even though the attempt is not.
    it "records one representative not_found event per day, and keeps trying" do
      unknown = { "X-Installation-Id" => "never-registered-#{SecureRandom.uuid}" }
      failures = ProductAnalyticsEvent.where(event_name: "installation_link_failed")

      expect do
        6.times do
          sign_in user # see the note on authenticated_requests above
          authenticated_request(unknown)
          expect(response).to have_http_status(:ok)
        end
      end.to change { failures.count }.by(1)

      expect(failures.last.properties["link_result"]).to eq("not_found")
    end
  end
end

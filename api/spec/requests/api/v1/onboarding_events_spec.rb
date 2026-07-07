require "rails_helper"

RSpec.describe "Api::V1::OnboardingEvents", type: :request do
  let(:user) { create(:user) }

  describe "POST /api/v1/onboarding_events" do
    it "requires authentication" do
      expect {
        post "/api/v1/onboarding_events",
             params: { event_name: "onboarding_started" },
             headers: { "Content-Type" => "application/json" }
      }.not_to change(OnboardingEvent, :count)

      expect(response).not_to have_http_status(:no_content)
    end

    context "when authenticated" do
      before { sign_in user }

      it "persists the event under the current user, ignoring any user_id in the body" do
        other_user = create(:user)

        post "/api/v1/onboarding_events", params: {
          user_id: other_user.id,
          event_name: "onboarding_flow_selected",
          onboarding_flow: "quick",
          step_name: "choose_flow",
          metadata: { selected_option: "quick" }
        }

        expect(response).to have_http_status(:no_content)
        event = OnboardingEvent.last
        expect(event.user_id).to eq(user.id)
        expect(event.onboarding_flow).to eq("quick")
      end

      it "does not raise and does not persist for an invalid event_name" do
        expect {
          post "/api/v1/onboarding_events", params: { event_name: "invalid_event" }
        }.not_to change(OnboardingEvent, :count)

        expect(response).to have_http_status(:no_content)
      end

      it "defaults occurred_at to now when absent" do
        post "/api/v1/onboarding_events", params: { event_name: "onboarding_started" }

        expect(OnboardingEvent.last.occurred_at).to be_within(5.seconds).of(Time.current)
      end
    end
  end
end

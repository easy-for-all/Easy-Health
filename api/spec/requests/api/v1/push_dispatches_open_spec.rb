require "rails_helper"

RSpec.describe "Api::V1::PushDispatches open tracking", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  def create_dispatch(status: "provider_accepted")
    PushDispatch.create!(
      user: user, notification_type: "activation_reminder", campaign_key: "first_workout_not_started_2h",
      idempotency_key: "d:#{SecureRandom.hex(4)}", status: status
    )
  end

  it "stamps opened_at and records the open funnel event" do
    dispatch = create_dispatch

    post "/api/v1/push_dispatches/#{dispatch.id}/opened"

    expect(response).to have_http_status(:ok)
    expect(dispatch.reload.opened_at).to be_present
    expect(dispatch.status).to eq("opened")
    expect(UserEvent.exists?(user: user, event_name: "push_opened")).to be(true)
  end

  it "never exposes another user's dispatch" do
    other = create(:user)
    dispatch = PushDispatch.create!(user: other, notification_type: "activation_reminder",
                                    idempotency_key: "d:#{SecureRandom.hex(4)}", status: "provider_accepted")

    post "/api/v1/push_dispatches/#{dispatch.id}/opened"

    expect(response).to have_http_status(:not_found)
    expect(dispatch.reload.opened_at).to be_nil
  end
end

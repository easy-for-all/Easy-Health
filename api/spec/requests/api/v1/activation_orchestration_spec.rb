require "rails_helper"

# EVENT ORCHESTRATION != PUSH DELIVERY ELIGIBILITY.
#
# Regression for the production case where user 540 (Android build 63) generated
# activation_workout_created and the UserEvent was born with
# make_delivery_status=disabled, make_attempts_count=0 and
# make_last_error=event_not_orchestration — because the event had no entry in
# config/communication_events.yml.
#
# The three acts below are the executable proof of the separation:
#   A. the fact reaches Make even with no token, no permission and push off;
#   B. the delivery job actually posts it, and the payload carries no token;
#   C. when Make later asks for a push, EasyHealth still refuses on consent.
RSpec.describe "activation_workout_created orchestration", type: :request do
  # Deliberately the worst case for push: Android user who never opted in, has
  # no device token, and has push disabled at every level.
  let(:user) { create(:user, paid_plan: true) }
  let(:exercise) do
    Exercise.create!(name: "Rosca com Halteres", exercise_type: "musculacao", muscle_group: "biceps")
  end

  def make_env
    {
      "MAKE_WEBHOOK_ENABLED" => "true",
      "MAKE_WEBHOOK_URL" => "https://make.example/webhook",
      "MAKE_WEBHOOK_SECRET" => "secret",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => nil,
      "MAKE_WEBHOOK_PAYLOAD_MODE" => "minimal"
    }
  end

  before do
    user.notification_preferences!.update!(push_enabled: false, workout_reminders_enabled: false)
    allow(MakeWebhookDeliveryJob).to receive(:perform_later)
    allow_any_instance_of(WorkoutPlanGeneratorService).to receive(:call) do
      plan = user.workout_plans.create!(active: true)
      day = plan.workout_days.create!(name: "Full Body A", day_of_week: Date.current.wday)
      day.workout_day_exercises.create!(exercise: exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: 0)
      plan
    end
    allow_any_instance_of(WorkoutPlanGeneratorService).to receive(:plan_summary).and_return({})
    sign_in user
  end

  def create_first_plan
    with_env(make_env) do
      post "/api/v1/workout_plan/regenerate",
           params: { modality: "ai_choice" },
           headers: { "X-Platform" => "android" }
    end
    expect(response).to have_http_status(:ok)
    UserEvent.find_by!(user: user, event_name: "activation_workout_created")
  end

  # --- A. Producing the event -----------------------------------------------
  #
  # Asserts on eligibility and on the enqueue, NOT on make_delivery_status ==
  # "pending": an intermediate status is an implementation detail that would
  # make this regression test fail for the wrong reasons.
  describe "A. producing the event with no push consent" do
    it "is eligible for orchestration and hands the event to the delivery job" do
      expect(user.device_tokens.active).to be_empty
      expect(user.notification_preferences.push_enabled).to be(false)

      event = create_first_plan

      with_env(make_env) do
        expect(
          MakeWebhookEligibility.eligible_for_new_event?(user: user, event_name: "activation_workout_created")
        ).to be(true)
      end

      expect(MakeWebhookDeliveryJob).to have_received(:perform_later).with(event.id)
      expect(event.make_last_error).not_to eq("event_not_orchestration")
      expect(event.make_delivery_channels_list).to include("push")
      expect(event.origin_surface).to eq("android")
    end

    it "is an orchestration event in the catalog, not an uncatalogued one" do
      expect(CommunicationEvents.orchestration?("activation_workout_created")).to be(true)
      expect(CommunicationEvents.analytics_only?("activation_workout_created")).to be(false)
      expect(CommunicationEvents.uncatalogued_event_names).to be_empty
    end
  end

  # --- B. Delivering it ------------------------------------------------------
  describe "B. running the delivery job" do
    it "posts the event to Make and records the accepted delivery" do
      event = create_first_plan
      captured_body = nil

      with_env(make_env) { captured_body = deliver!(event) }

      event.reload
      expect(event.make_delivery_status).to eq("accepted_by_make")
      expect(event.make_attempts_count).to eq(1)
      expect(event.make_last_http_status).to eq(200)
    end

    it "sends push as a candidate channel and never leaks a device token" do
      event = create_first_plan
      body = nil

      with_env(make_env) { body = deliver!(event) }

      payload = JSON.parse(body)
      expect(payload["event_name"]).to eq("activation_workout_created")
      expect(payload["origin_surface"]).to eq("android")
      expect(payload.dig("delivery", "candidate_channels")).to include("push")
      expect(payload.dig("delivery", "channels")).to include("push")
      expect(payload.dig("push", "notification_type")).to eq("activation_reminder")
      expect(payload.dig("push", "route")).to eq("/workouts/ready")

      # The user has no token at all here, but even when they do, the token is
      # EasyHealth's alone: Make decides, EasyHealth addresses the device.
      expect(body).not_to match(/fcm|device_token|registration_id/i)
      expect(deep_keys(payload)).not_to include("token")
    end
  end

  # --- C. Make asks for a push anyway ---------------------------------------
  describe "C. push delivery eligibility still applies" do
    let(:dispatch_token) { "make-dispatch-secret" }

    def push_env
      {
        "MAKE_PUSH_ORCHESTRATION_ENABLED" => "true",
        "MAKE_PUSH_DISPATCH_TOKEN" => dispatch_token,
        "MAKE_PUSH_DISPATCH_TOKEN_CURRENT" => nil,
        "MAKE_PUSH_DISPATCH_TOKEN_PREVIOUS" => nil,
        "MAKE_PUSH_RATE_LIMIT_PER_USER" => "50"
      }
    end

    def request_push(target = user)
      expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
      with_env(push_env) do
        post "/api/v1/integrations/make/push_dispatches",
             params: {
               event_id: "evt_#{SecureRandom.hex(4)}",
               user_id: target.id,
               notification_type: "activation_reminder",
               campaign_key: "activation_workout_created",
               title: "Seu treino está pronto",
               body: "Bora começar?",
               route: "/workouts/ready"
             }.to_json,
             headers: { "Authorization" => "Bearer #{dispatch_token}", "CONTENT_TYPE" => "application/json" }
      end
      JSON.parse(response.body)
    end

    it "skips with global_opt_out when push is disabled" do
      create_first_plan

      expect(request_push).to include("status" => "skipped", "skip_reason" => "global_opt_out", "sent" => false)
      expect(PushDispatch.last.status).to eq("skipped")
      expect(PushDispatch.last.skip_reason).to eq("global_opt_out")
    end

    it "skips with no_active_token when push is enabled but no device is registered" do
      create_first_plan
      user.notification_preferences.update!(push_enabled: true, workout_reminders_enabled: true)

      expect(request_push).to include("status" => "skipped", "skip_reason" => "no_active_token")
    end

    it "skips with no_preferences when the consent flow never ran" do
      other = create(:user)
      expect(other.notification_preferences).to be_nil

      expect(request_push(other)).to include("status" => "skipped", "skip_reason" => "no_preferences")
    end
  end

  # Runs the real delivery job against a stubbed Net::HTTP and returns the
  # request body that was posted.
  def deliver!(event)
    captured_body = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return("ok")
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request) do |request|
      captured_body = request.body
      response
    end

    MakeWebhookDeliveryJob.new.perform(event.id)
    captured_body
  end

  def deep_keys(object)
    case object
    when Hash then object.keys + object.values.flat_map { |value| deep_keys(value) }
    when Array then object.flat_map { |value| deep_keys(value) }
    else []
    end
  end
end

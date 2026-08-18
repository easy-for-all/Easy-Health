require "rails_helper"
require "rake"

RSpec.describe "make event tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("make:preview_event")
  end

  let(:preview_task) { Rake::Task["make:preview_event"] }
  let(:test_task) { Rake::Task["make:test_event"] }
  let(:audit_task) { Rake::Task["make_webhook:audit"] }
  let(:retry_pending_task) { Rake::Task["make_webhook:retry_pending"] }
  let(:user) { create(:user, marketing_consent: true, email: "task-user@example.com") }

  before do
    preview_task.reenable
    test_task.reenable
    audit_task.reenable
    retry_pending_task.reenable
    ENV.delete("CHANNELS")
    ENV.delete("DRY_RUN")
    ENV.delete("CONFIRM_PRODUCTION_MAKE_TEST")
    ENV.delete("EXPECT_DATA")
    ENV.delete("HOURS")
    ENV.delete("LIMIT")
    ENV.delete("OBSERVABILITY_MAKE_BACKLOG_AGE_MINUTES")
  end

  after do
    ENV.delete("CHANNELS")
    ENV.delete("DRY_RUN")
    ENV.delete("CONFIRM_PRODUCTION_MAKE_TEST")
    ENV.delete("EXPECT_DATA")
    ENV.delete("HOURS")
    ENV.delete("LIMIT")
    ENV.delete("OBSERVABILITY_MAKE_BACKLOG_AGE_MINUTES")
  end

  it "previews a v2 payload without persisting a user event" do
    user

    with_env("MAKE_EVENT_SCHEMA_VERSION" => "2") do
      expect do
        expect { preview_task.invoke(user.email, "first_workout_created") }
          .to output(/"schema_version": 2/).to_stdout
      end.not_to change(UserEvent, :count)
    end
  end

  it "dry-runs the test task without sending" do
    user

    with_env(
      "MAKE_EVENT_SCHEMA_VERSION" => "2",
      "DRY_RUN" => "true",
      "CHANNELS" => "email"
    ) do
      expect(MakeWebhookClient).not_to receive(:new)
      expect do
        expect { test_task.invoke(user.email, "first_workout_created") }
          .to output(/Dry   : true/).to_stdout
      end.not_to change(UserEvent, :count)
    end
  end

  it "creates a test event and delegates delivery when configured" do
    client = instance_double(MakeWebhookClient)
    result = MakeWebhookClient::Result.new(status: "accepted_by_make")

    allow(MakeWebhookClient).to receive(:new).and_return(client)
    allow(client).to receive(:deliver).and_return(result)

    with_env(
      "MAKE_EVENT_SCHEMA_VERSION" => "2",
      "MAKE_WEBHOOK_ENABLED" => "true",
      "MAKE_WEBHOOK_URL" => "https://make.example/webhook",
      "MAKE_WEBHOOK_SECRET" => "secret",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => "first_workout_created"
    ) do
      expect do
        expect { test_task.invoke(user.email, "first_workout_created") }
          .to output(/Result : accepted_by_make/).to_stdout
      end.to change(UserEvent.where(event_name: "first_workout_created"), :count).by(1)
    end

    event = UserEvent.where(event_name: "first_workout_created").last
    expect(event.metadata["trigger_source"]).to eq("manual_test")
    expect(event.payload_json["schema_version"]).to eq(2)
    expect(client).to have_received(:deliver).with(event, delivery_channels: nil)
  end

  it "reports an expected-but-empty database without raising SystemExit" do
    with_env("EXPECT_DATA" => "1") do
      expect { audit_task.invoke }
        .to output(/"ok": false.*"result": "empty_database"/m).to_stdout
    end
  end

  it "prints recent Make delivery rows when data exists" do
    event = UserEvent.create!(
      user: user,
      event_name: "first_workout_created",
      occurred_at: Time.current,
      make_delivery_status: "accepted_by_make",
      make_processing_status: "completed",
      make_attempts_count: 1,
      make_last_http_status: 200,
      make_delivery_channels: [ "email" ],
      make_destination: "relationship_email"
    )

    expect { audit_task.invoke }
      .to output(/"ok": true.*"event_name": "first_workout_created".*"delivery_status": "accepted_by_make"/m).to_stdout

    expect(event.reload.make_delivery_status).to eq("accepted_by_make")
  end

  it "re-drives old pending, due retrying, and stale sending events" do
    old_pending = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                    occurred_at: Time.current, make_delivery_status: "pending")
    old_pending.update_columns(created_at: 2.hours.ago, updated_at: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
    fresh_pending = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                      occurred_at: Time.current, make_delivery_status: "pending")
    due_retrying = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                     occurred_at: Time.current, make_delivery_status: "retrying",
                                     make_next_retry_at: 1.minute.ago)
    future_retrying = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                        occurred_at: Time.current, make_delivery_status: "retrying",
                                        make_next_retry_at: 1.hour.from_now)
    stale_sending = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                      occurred_at: Time.current, make_delivery_status: "sending",
                                      make_last_attempt_at: 10.minutes.ago)
    fresh_sending = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                      occurred_at: Time.current, make_delivery_status: "sending",
                                      make_last_attempt_at: 1.minute.ago)

    client = instance_double(MakeWebhookClient)
    allow(MakeWebhookClient).to receive(:new).and_return(client)
    allow(client).to receive(:deliver).and_return(MakeWebhookClient::Result.new(status: "accepted_by_make"))

    with_env("OBSERVABILITY_MAKE_BACKLOG_AGE_MINUTES" => "30", "LIMIT" => "200") do
      expect { retry_pending_task.invoke }.to output(/Make pending retry/).to_stdout
    end

    expect(client).to have_received(:deliver).with(old_pending)
    expect(client).to have_received(:deliver).with(due_retrying)
    expect(client).to have_received(:deliver).with(stale_sending)
    expect(client).not_to have_received(:deliver).with(fresh_pending)
    expect(client).not_to have_received(:deliver).with(future_retrying)
    expect(client).not_to have_received(:deliver).with(fresh_sending)
    expect(stale_sending.reload.make_last_error).to eq(MakePendingDeliveryRetry::ABANDONED_SENDING_ERROR)
  end
end

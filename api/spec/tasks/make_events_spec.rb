require "rails_helper"
require "rake"

RSpec.describe "make event tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("make:preview_event")
  end

  let(:preview_task) { Rake::Task["make:preview_event"] }
  let(:test_task) { Rake::Task["make:test_event"] }
  let(:user) { create(:user, marketing_consent: true, email: "task-user@example.com") }

  before do
    preview_task.reenable
    test_task.reenable
    ENV.delete("CHANNELS")
    ENV.delete("DRY_RUN")
    ENV.delete("CONFIRM_PRODUCTION_MAKE_TEST")
  end

  after do
    ENV.delete("CHANNELS")
    ENV.delete("DRY_RUN")
    ENV.delete("CONFIRM_PRODUCTION_MAKE_TEST")
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
      "CHANNELS" => "email,push"
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
    result = MakeWebhookClient::Result.new(status: "delivered")

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
          .to output(/Result : delivered/).to_stdout
      end.to change(UserEvent.where(event_name: "first_workout_created"), :count).by(1)
    end

    event = UserEvent.where(event_name: "first_workout_created").last
    expect(event.metadata["trigger_source"]).to eq("manual_test")
    expect(event.payload_json["schema_version"]).to eq(2)
    expect(client).to have_received(:deliver).with(event, delivery_channels: nil)
  end
end

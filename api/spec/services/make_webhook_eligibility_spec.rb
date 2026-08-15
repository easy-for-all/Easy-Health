require "rails_helper"

RSpec.describe MakeWebhookEligibility do
  let(:user) { create(:user, marketing_consent: true) }

  let(:make_env) do
    {
      "MAKE_WEBHOOK_ENABLED" => "true",
      "MAKE_WEBHOOK_URL" => "https://make.example/webhook",
      "MAKE_WEBHOOK_SECRET" => "secret",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => ""
    }
  end

  def as_production
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
  end

  describe "the allowlist derives from the catalog" do
    # THE regression this whole layer exists to prevent: an orchestration event
    # configured in communication_events.yml silently becoming "disabled"
    # because MAKE_WEBHOOK_ALLOWED_EVENTS did not happen to list it.
    it "allows every orchestration event even with an empty legacy env allowlist" do
      with_env(make_env) do
        CommunicationEvents.orchestration_event_names.each do |event_name|
          expect(described_class.event_allowed?(event_name)).to be(true), "#{event_name} bloqueado"
        end
      end
    end

    it "matches the catalog exactly" do
      with_env(make_env) do
        expect(described_class.allowed_events).to match_array(CommunicationEvents.orchestration_event_names)
      end
    end

    it "does not allow an event that has no catalog entry" do
      with_env(make_env) do
        expect(described_class.event_allowed?("workout_started")).to be(false)
      end
    end

    it "cannot be narrowed by the legacy env var" do
      with_env(make_env.merge("MAKE_WEBHOOK_ALLOWED_EVENTS" => "user_created")) do
        expect(described_class.event_allowed?("first_workout_not_started_2h")).to be(true)
      end
    end
  end

  describe "the legacy env allowlist" do
    it "can add an uncatalogued event outside production" do
      with_env(make_env.merge("MAKE_WEBHOOK_ALLOWED_EVENTS" => "workout_started")) do
        expect(described_class.event_allowed?("workout_started")).to be(true)
        expect(described_class.orchestration_event?("workout_started")).to be(false)
      end
    end

    it "is inert in production without the explicit escape hatch" do
      as_production
      with_env(make_env.merge("MAKE_WEBHOOK_ALLOWED_EVENTS" => "workout_started")) do
        expect(described_class.event_allowed?("workout_started")).to be(false)
      end
    end

    it "works in production only with the escape hatch set" do
      as_production
      env = make_env.merge(
        "MAKE_WEBHOOK_ALLOWED_EVENTS" => "workout_started",
        "MAKE_WEBHOOK_ALLOW_LEGACY_ENV_EVENTS" => "true"
      )

      with_env(env) { expect(described_class.event_allowed?("workout_started")).to be(true) }
    end

    it "reports an env-only event as drift" do
      with_env(make_env.merge("MAKE_WEBHOOK_ALLOWED_EVENTS" => "workout_started")) do
        expect(described_class.allowlist_drift[:env_only]).to eq(%w[workout_started])
      end
    end
  end

  describe "hard gates per channel" do
    it "keeps a push-only event deliverable for a user with no email consent" do
      user.update!(marketing_consent: false, unsubscribed_at: Time.current, email_bounced_at: Time.current)

      with_env(make_env) do
        expect(described_class.deliverable_channels(user, "first_workout_not_started_2h")).to eq(%w[push])
        expect(described_class.eligible_for_new_event?(user: user, event_name: "first_workout_not_started_2h"))
          .to be(true)
      end
    end

    it "closes the email channel for a user with no email consent" do
      user.update!(marketing_consent: false)

      with_env(make_env) do
        expect(described_class.deliverable_channels(user, "user_created")).to be_empty
        expect(described_class.eligible_for_new_event?(user: user, event_name: "user_created")).to be(false)
      end
    end

    it "narrows a multichannel event instead of suppressing it" do
      user.update!(marketing_consent: false)

      with_env(make_env) do
        expect(described_class.deliverable_channels(user, "user_inactive_7_days")).to eq(%w[push])
      end
    end

    it "keeps both channels for a fully consented user" do
      with_env(make_env) do
        expect(described_class.deliverable_channels(user, "user_inactive_7_days")).to match_array(%w[push email])
      end
    end

    # Push eligibility is decided at dispatch, never here — the fact must reach
    # Make so Make can decide whether to ask for a push at all.
    it "ignores push preferences and device tokens" do
      user.notification_preferences!.update!(push_enabled: false, workout_reminders_enabled: false)

      with_env(make_env) do
        expect(described_class.deliverable_channels(user, "user_inactive_3_days")).to eq(%w[push])
      end
    end

    # The production case: user 540 on Android, no device token, push off at
    # every level. The fact must still reach Make — whether it ever becomes a
    # notification is Make::PushDispatchRequest's call, later.
    it "keeps activation_workout_created eligible with no token and push disabled" do
      user.notification_preferences!.update!(push_enabled: false, workout_reminders_enabled: false)
      expect(user.device_tokens.active).to be_empty

      with_env(make_env) do
        expect(described_class.orchestration_event?("activation_workout_created")).to be(true)
        expect(described_class.deliverable_channels(user, "activation_workout_created")).to eq(%w[push])
        expect(described_class.eligible_for_new_event?(user: user, event_name: "activation_workout_created"))
          .to be(true)
        expect(described_class.ineligibility_reason(
          UserEvent.new(user: user, event_name: "activation_workout_created")
        )).not_to eq("event_not_orchestration")
      end
    end

    it "blocks every channel for a deleted or anonymized account" do
      with_env(make_env) do
        expect(described_class.account_valid?(build(:user, deletion_requested_at: Time.current))).to be(false)
        expect(described_class.account_valid?(build(:user, anonymized_at: Time.current))).to be(false)
        expect(described_class.account_valid?(user)).to be(true)
      end
    end
  end

  describe "#ineligibility_reason" do
    let(:event) { UserEvent.new(user: user, event_name: "first_workout_completed") }

    it "reports the webhook being off" do
      with_env(make_env.merge("MAKE_WEBHOOK_ENABLED" => "false")) do
        expect(described_class.ineligibility_reason(event)).to eq("make_webhook_disabled_or_unconfigured")
      end
    end

    it "reports a deleted account" do
      user.update!(deletion_requested_at: Time.current)

      with_env(make_env) do
        expect(described_class.ineligibility_reason(event)).to eq("user_deleted_or_anonymized")
      end
    end

    it "reports an event with no catalog entry" do
      with_env(make_env) do
        expect(described_class.ineligibility_reason(UserEvent.new(user: user, event_name: "workout_started")))
          .to eq("event_not_orchestration")
      end
    end

    it "reports every channel being closed" do
      user.update!(marketing_consent: false)

      with_env(make_env) do
        expect(described_class.ineligibility_reason(UserEvent.new(user: user, event_name: "user_created")))
          .to eq("no_deliverable_channel")
      end
    end
  end

  describe "the deprecated relationship gate" do
    it "still combines the account and email rules" do
      expect(described_class.user_eligible_for_relationship?(user)).to be(true)

      user.update!(marketing_consent: false)
      expect(described_class.user_eligible_for_relationship?(user)).to be(false)
    end
  end
end

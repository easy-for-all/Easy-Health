require "rails_helper"

RSpec.describe RelationshipMessageService do
  let(:user) { create(:user) }

  let(:base_payload) do
    {
      "user_id"       => user.id.to_s,
      "event_name"    => "user_created",
      "journey_key"   => "onboarding",
      "step_key"      => "welcome_email",
      "channel"       => "email",
      "provider"      => "brevo",
      "template_key"  => "EH_001_WELCOME",
      "subject"       => "Bem-vindo",
      "recipient_email" => "user@example.com",
      "metadata"      => { "make_execution_id" => "exec-abc", "make_scenario" => "easyhealth_v1" }
    }
  end

  def call(overrides = {})
    described_class.record_from_make!(payload: base_payload.merge(overrides))
  end

  describe ".record_from_make!" do
    context "with status: sent" do
      let(:result) { call("status" => "sent", "sent_at" => "2026-06-28T15:00:00Z") }

      it "returns success" do
        expect(result).to be_success
      end

      it "persists the record" do
        expect { result }.to change(RelationshipMessage, :count).by(1)
      end

      it "sets sent_at from payload" do
        record = result.record
        expect(record.sent_at).to be_within(1.second).of(Time.parse("2026-06-28T15:00:00Z"))
      end

      it "sets status to sent" do
        expect(result.record.status).to eq("sent")
      end

      it "stores recipient_email" do
        expect(result.record.recipient_email).to eq("user@example.com")
      end
    end

    context "with status: failed" do
      let(:result) { call("status" => "failed", "error_message" => "Brevo API error") }

      it "returns success" do
        expect(result).to be_success
      end

      it "sets failed_at" do
        expect(result.record.failed_at).to be_present
      end

      it "stores error_message" do
        expect(result.record.error_message).to eq("Brevo API error")
      end
    end

    context "with status: skipped" do
      let(:result) { call("status" => "skipped") }

      it "sets skipped_at" do
        expect(result.record.skipped_at).to be_present
      end
    end

    context "idempotency" do
      it "does not create a duplicate when called twice with the same execution_id" do
        call("status" => "sent")
        expect { call("status" => "sent") }.not_to change(RelationshipMessage, :count)
      end

      it "updates the existing record on the second call" do
        first  = call("status" => "sent")
        second = call("status" => "delivered")
        expect(second.record.id).to eq(first.record.id)
        expect(second.record.status).to eq("delivered")
      end
    end

    context "metadata sanitization" do
      let(:result) do
        call(
          "status"   => "sent",
          "metadata" => { "make_execution_id" => "x", "secret" => "should_be_removed", "safe_key" => "kept" }
        )
      end

      it "removes sensitive keys from metadata_json" do
        expect(result.record.metadata_json).not_to have_key("secret")
      end

      it "keeps safe keys" do
        expect(result.record.metadata_json).to have_key("safe_key")
      end
    end

    context "when user is not found" do
      let(:result) { call("user_id" => "999999") }

      it "returns failure with user_not_found" do
        expect(result).not_to be_success
        expect(result.error).to eq("user_not_found")
      end

      it "does not persist a record" do
        expect { result }.not_to change(RelationshipMessage, :count)
      end
    end

    context "when status is invalid" do
      let(:result) { call("status" => "nonexistent") }

      it "returns failure" do
        expect(result).not_to be_success
        expect(result.error).to eq("invalid_status")
      end
    end

    context "when channel is invalid" do
      let(:result) { call("status" => "sent", "channel" => "fax") }

      it "returns failure" do
        expect(result).not_to be_success
        expect(result.error).to eq("missing_channel")
      end
    end

    context "with tracking status (delivered) and existing provider_message_id" do
      let!(:existing) do
        create(:relationship_message, user: user, status: "sent",
               provider_message_id: "brevo-123")
      end

      let(:result) do
        call(
          "status"              => "delivered",
          "provider_message_id" => "brevo-123",
          "metadata"            => { "make_execution_id" => nil }
        )
      end

      it "updates the existing record instead of creating a new one" do
        expect { result }.not_to change(RelationshipMessage, :count)
        expect(existing.reload.status).to eq("delivered")
      end
    end

    context "without make_execution_id (no idempotency_key)" do
      let(:result) { call("status" => "sent", "metadata" => {}) }

      it "still persists the record" do
        expect(result).to be_success
        expect(result.record.idempotency_key).to be_nil
      end

      it "allows a second creation with same data" do
        call("status" => "sent", "metadata" => {})
        expect { call("status" => "sent", "metadata" => {}) }.to change(RelationshipMessage, :count).by(1)
      end
    end
  end
end

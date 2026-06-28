require "rails_helper"

RSpec.describe RelationshipMessage, type: :model do
  let(:user) { create(:user) }

  describe "associations" do
    it "belongs to user" do
      message = build(:relationship_message, user: user)
      expect(message.user).to eq(user)
    end

    it "allows user_event to be nil" do
      message = build(:relationship_message, user: user, user_event: nil)
      expect(message).to be_valid
    end
  end

  describe "validations" do
    it "is valid with all required fields" do
      expect(build(:relationship_message, user: user)).to be_valid
    end

    it "requires event_name" do
      message = build(:relationship_message, user: user, event_name: nil)
      expect(message).not_to be_valid
      expect(message.errors[:event_name]).to be_present
    end

    it "rejects invalid channel" do
      message = build(:relationship_message, user: user, channel: "fax")
      expect(message).not_to be_valid
    end

    it "rejects invalid provider" do
      message = build(:relationship_message, user: user, provider: "unknown")
      expect(message).not_to be_valid
    end

    it "rejects invalid status" do
      message = build(:relationship_message, user: user, status: "bogus")
      expect(message).not_to be_valid
    end

    context "idempotency_key uniqueness" do
      before { create(:relationship_message, user: user, idempotency_key: "unique-key") }

      it "rejects duplicate idempotency_key" do
        duplicate = build(:relationship_message, user: user, idempotency_key: "unique-key")
        expect(duplicate).not_to be_valid
      end
    end

    it "allows multiple records with nil idempotency_key" do
      create(:relationship_message, user: user)
      expect(build(:relationship_message, user: user)).to be_valid
    end
  end

  describe "constants" do
    it "defines CHANNELS" do
      expect(described_class::CHANNELS).to include("email", "push", "whatsapp", "sms", "in_app")
    end

    it "defines PROVIDERS" do
      expect(described_class::PROVIDERS).to include("brevo", "sendgrid", "make", "internal")
    end

    it "defines STATUSES" do
      expect(described_class::STATUSES).to include("pending", "sent", "failed", "skipped", "delivered", "opened", "clicked")
    end
  end
end

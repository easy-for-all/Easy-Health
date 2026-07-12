require "rails_helper"

RSpec.describe User do
  describe "associations" do
    it "does not depend on the removed ai_chat_messages table when destroyed" do
      user = create(:user)

      expect(described_class.reflect_on_association(:ai_chat_messages)).to be_nil
      expect { user.destroy! }.not_to raise_error
    end
  end

  describe "#active_for_authentication?" do
    it "is true for a regular account" do
      user = create(:user)

      expect(user.active_for_authentication?).to be true
    end

    it "is false once the account has been anonymized" do
      user = create(:user, anonymized_at: Time.current)

      expect(user.active_for_authentication?).to be false
    end
  end

  describe "email_not_blocked validation" do
    it "rejects creating a new user with a blocked email" do
      BlockedEmail.block!(email: "blocked@example.com", user_id: 1)

      user = build(:user, email: "blocked@example.com")

      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "allows a non-blocked email" do
      user = build(:user, email: "free@example.com")

      expect(user).to be_valid
    end
  end

  describe ".from_omniauth" do
    def auth_double(uid:, email:, name: "Test User")
      info = double("info", email: email, name: name, image: nil)
      double("auth", provider: "google_oauth2", uid: uid, info: info)
    end

    let(:full_consent) { { terms_accepted: true, privacy_accepted: true, source: "web" } }

    it "creates a new user for a fresh identity when consent is given" do
      user = described_class.from_omniauth(auth_double(uid: "uid-1", email: "new@example.com"), consent: full_consent)

      expect(user).to be_persisted
      expect(user.provider).to eq("google_oauth2")
      expect(user.uid).to eq("uid-1")
      expect(user.terms_accepted_at).to be_present
      expect(user.privacy_policy_accepted_at).to be_present
      expect(user.terms_version).to eq(User::CURRENT_TERMS_VERSION)
      expect(user.consent_source).to eq("web")
    end

    it "raises ConsentRequiredError when creating a new user without consent" do
      expect {
        described_class.from_omniauth(auth_double(uid: "uid-9", email: "noconsent@example.com"))
      }.to raise_error(User::ConsentRequiredError)
      expect(User.find_by(email: "noconsent@example.com")).to be_nil
    end

    it "raises ConsentRequiredError when only one of terms/privacy is accepted" do
      expect {
        described_class.from_omniauth(
          auth_double(uid: "uid-10", email: "partial@example.com"),
          consent: { terms_accepted: true, privacy_accepted: false }
        )
      }.to raise_error(User::ConsentRequiredError)
    end

    it "authenticates an existing user without consent and keeps their acceptance dates" do
      accepted_at = 2.days.ago
      existing = create(:user, provider: "google_oauth2", uid: "uid-11",
                               terms_accepted_at: accepted_at, privacy_policy_accepted_at: accepted_at)

      user = described_class.from_omniauth(auth_double(uid: "uid-11", email: existing.email))

      expect(user.id).to eq(existing.id)
      expect(user.reload.terms_accepted_at).to be_within(1.second).of(accepted_at)
    end

    it "returns the same anonymized user when provider/uid match (no new record is created)" do
      anonymized = create(:user, provider: "google_oauth2", uid: "uid-2", anonymized_at: Time.current)

      user = described_class.from_omniauth(auth_double(uid: "uid-2", email: "irrelevant@example.com"))

      expect(user.id).to eq(anonymized.id)
      expect(user.anonymized_at).to be_present
    end

    it "raises BlockedEmailError instead of creating a new account for a blocked email" do
      BlockedEmail.block!(email: "blocked@example.com", user_id: 1)

      expect {
        described_class.from_omniauth(auth_double(uid: "uid-3", email: "blocked@example.com"))
      }.to raise_error(User::BlockedEmailError)
    end
  end
end

require "rails_helper"

RSpec.describe MobileAuthCode do
  let(:user) { create(:user) }

  describe ".issue_for!" do
    it "stores only a digest for the generated code" do
      code = described_class.issue_for!(user: user, platform: "android")
      auth_code = described_class.last

      expect(code).to be_present
      expect(auth_code.code_digest).to eq(described_class.digest(code))
      expect(auth_code.code_digest).not_to eq(code)
      expect(auth_code.expires_at).to be_within(5.seconds).of(described_class::CODE_TTL.from_now)
    end

    it "rejects unsupported platforms" do
      expect {
        described_class.issue_for!(user: user, platform: "desktop")
      }.to raise_error(described_class::InvalidPlatformError)
    end
  end

  describe ".redeem!" do
    it "marks a valid code as used" do
      code = described_class.issue_for!(user: user, platform: "android")

      auth_code = described_class.redeem!(code: code, platform: "android")

      expect(auth_code.user).to eq(user)
      expect(auth_code.used_at).to be_present
    end

    it "rejects an expired code" do
      create(:mobile_auth_code, user: user, code: "expired", expires_at: 1.minute.ago)

      expect {
        described_class.redeem!(code: "expired", platform: "android")
      }.to raise_error(described_class::ExpiredCodeError)
    end

    it "rejects a used code" do
      create(:mobile_auth_code, user: user, code: "used", used_at: Time.current)

      expect {
        described_class.redeem!(code: "used", platform: "android")
      }.to raise_error(described_class::UsedCodeError)
    end
  end
end

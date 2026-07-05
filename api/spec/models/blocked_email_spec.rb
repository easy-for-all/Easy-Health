require "rails_helper"

RSpec.describe BlockedEmail do
  describe ".block!" do
    it "stores a normalized (downcased, stripped) email" do
      described_class.block!(email: " Foo@Example.com ", user_id: 1)

      expect(described_class.exists?(email: "foo@example.com")).to be true
    end
  end

  describe ".blocked?" do
    it "returns true for an email that was blocked, regardless of case" do
      described_class.block!(email: "foo@example.com", user_id: 1)

      expect(described_class.blocked?("FOO@example.com")).to be true
    end

    it "returns false for an email that was never blocked" do
      expect(described_class.blocked?("bar@example.com")).to be false
    end

    it "returns false for a blank email" do
      expect(described_class.blocked?(nil)).to be false
    end
  end
end

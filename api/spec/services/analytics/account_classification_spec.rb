require "rails_helper"

RSpec.describe Analytics::AccountClassification do
  def user_with(email, **attrs)
    create(:user, email: email, **attrs)
  end

  describe ".for" do
    it "classifies a Google Play pre-launch account as automated_test" do
      user = user_with("pljgflkpu2y4wj7ie4cwlgpcay-00@cloudtestlabaccounts.com")

      expect(described_class.for(user)).to eq(:automated_test)
    end

    it "classifies the known internal addresses as internal" do
      described_class::DEFAULT_INTERNAL_EMAILS.each do |email|
        expect(described_class.for(user_with(email))).to eq(:internal), "expected #{email} to be internal"
      end
    end

    it "classifies an internal domain as internal" do
      expect(described_class.for(user_with("someone@easyhealth.art"))).to eq(:internal)
    end

    it "classifies a flagged test_account as internal" do
      expect(described_class.for(user_with("real@gmail.com", test_account: true))).to eq(:internal)
    end

    it "classifies an ordinary account as external" do
      expect(described_class.for(user_with("person@gmail.com"))).to eq(:external)
    end

    it "is case insensitive on the address" do
      expect(described_class.for(user_with("HELLO@EasyHealth.art"))).to eq(:internal)
    end

    it "does not classify by device: a real Pixel owner is still external" do
      # manufacturer == "Google" was explicitly rejected as a criterion — only
      # identity separates a test run from an acquisition.
      user = user_with("pixel.owner@gmail.com")
      create(:app_installation, user: user, platform: "android", device_manufacturer: "Google")

      expect(described_class.for(user)).to eq(:external)
    end
  end

  describe "scopes" do
    let!(:external) { user_with("person@gmail.com") }
    let!(:internal) { user_with("hello@easyhealth.art") }
    let!(:robot)    { user_with("abc-00@cloudtestlabaccounts.com") }

    it "keeps only external accounts in exclude_non_external" do
      ids = described_class.exclude_non_external(User.all).pluck(:id)

      expect(ids).to include(external.id)
      expect(ids).not_to include(internal.id, robot.id)
    end

    it "reports the robots on their own, apart from internal" do
      expect(described_class.automated_test_scope(User.all).pluck(:id)).to eq([ robot.id ])
      expect(described_class.internal_scope(User.all).pluck(:id)).to eq([ internal.id ])
    end

    it "agrees with .for on every record" do
      User.find_each do |user|
        in_external = described_class.exclude_non_external(User.where(id: user.id)).exists?
        expect(in_external).to eq(described_class.for(user) == :external),
                               "scope and .for disagree for #{user.email}"
      end
    end
  end

  describe "User.reportable" do
    it "drops Test Lab accounts, which used to count as real acquisition" do
      robot = user_with("xyz-00@cloudtestlabaccounts.com")
      real  = user_with("person@gmail.com")

      expect(User.reportable.pluck(:id)).to include(real.id)
      expect(User.reportable.pluck(:id)).not_to include(robot.id)
    end

    it "still excludes anonymized and deletion-requested accounts" do
      anonymized = user_with("gone@gmail.com", anonymized_at: Time.current)
      leaving    = user_with("leaving@gmail.com", deletion_requested_at: Time.current)

      expect(User.reportable.pluck(:id)).not_to include(anonymized.id, leaving.id)
    end
  end
end

require "rails_helper"

RSpec.describe User, ".reportable" do
  it "excludes test accounts, anonymized and deletion-requested users" do
    keeper    = create(:user)
    test_acc  = create(:user, test_account: true)
    anon      = create(:user, anonymized_at: Time.current)
    deleting  = create(:user, deletion_requested_at: Time.current)

    ids = User.reportable.pluck(:id)
    expect(ids).to include(keeper.id)
    expect(ids).not_to include(test_acc.id, anon.id, deleting.id)
  end

  it "excludes internal e-mail domains from ENV" do
    internal = create(:user, email: "qa@internal.test")
    external = create(:user, email: "real@example.com")

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ANALYTICS_INTERNAL_EMAIL_DOMAINS", "").and_return("internal.test")

    ids = User.reportable.pluck(:id)
    expect(ids).to include(external.id)
    expect(ids).not_to include(internal.id)
  end
end

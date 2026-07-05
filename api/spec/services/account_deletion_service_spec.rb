require "rails_helper"

RSpec.describe AccountDeletionService do
  let(:user) { create(:user, paid_plan: true) }

  before do
    user.subscription.update!(stripe_customer_id: "cus_real123")
  end

  it "anonymizes the user record and permanently marks the login as blocked" do
    original_email = user.email

    described_class.new(user).call
    user.reload

    expect(user.name).to eq("Deleted User")
    expect(user.email).to eq("deleted_#{user.id}@easyhealth.invalid")
    expect(user.anonymized_at).to be_present
    expect(user.deletion_requested_at).to be_present
    expect(user.active_for_authentication?).to be false
    expect(original_email).not_to eq(user.email)
  end

  it "clears stripe_customer_id instead of writing a fake id" do
    described_class.new(user).call

    expect(user.subscription.reload.stripe_customer_id).to be_nil
  end

  it "blocks the original email from being used to sign up again" do
    original_email = user.email

    described_class.new(user).call

    expect(BlockedEmail.blocked?(original_email)).to be true
  end

  it "destroys associated personal data" do
    user.workout_sessions.create!(completed_at: Time.current, duration_minutes: 30, exercise_logs: [])

    expect { described_class.new(user).call }.to change { user.workout_sessions.count }.to(0)
  end
end

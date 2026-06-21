require "rails_helper"

RSpec.describe FitnessProfile, type: :model do
  it "is valid with its safe defaults" do
    profile = described_class.new(user: create(:user))

    expect(profile).to be_valid
  end

  it "rejects a score outside the supported range" do
    profile = described_class.new(user: create(:user), consistency_score: 10.01)

    expect(profile).not_to be_valid
    expect(profile.errors[:consistency_score]).to be_present
  end

  it "enforces one fitness profile per user" do
    user = create(:user)
    described_class.create!(user: user)

    duplicate = described_class.new(user: user)
    expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end

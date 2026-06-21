require "rails_helper"
require "rake"

RSpec.describe "fitness_intelligence:recalculate" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("fitness_intelligence:recalculate")
  end

  let(:task) { Rake::Task["fitness_intelligence:recalculate"] }

  before do
    task.reenable
    ENV.delete("USER_ID")
  end

  after { ENV.delete("USER_ID") }

  it "backfills existing health profiles and remains idempotent" do
    user = create(:user)
    create(:health_profile, user: user)

    expect { task.invoke }.to output(/1 processed, 0 failed/).to_stdout
    expect(user.reload.fitness_profile).to be_present

    task.reenable
    expect { task.invoke }.to output(/1 processed, 0 failed/).to_stdout
    expect(FitnessProfile.where(user: user).count).to eq(1)
  end
end

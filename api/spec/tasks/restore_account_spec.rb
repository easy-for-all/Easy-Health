require "rails_helper"
require "rake"

RSpec.describe "account:restore" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("account:restore")
  end

  let(:task) { Rake::Task["account:restore"] }
  let(:user) { create(:user, paid_plan: true, anonymized_at: Time.current) }

  before do
    task.reenable
    ENV.delete("EMAIL")
    ENV.delete("USER_ID")
    ENV.delete("CONFIRM")
    user.subscription.update!(stripe_subscription_id: "sub_real123", stripe_customer_id: nil)

    stripe_subscription = double("Stripe::Subscription", customer: "cus_real123", status: "canceled")
    stripe_customer = double("Stripe::Customer", id: "cus_real123", email: "real@example.com", name: "Real Name")
    allow(Stripe::Subscription).to receive(:retrieve).with("sub_real123").and_return(stripe_subscription)
    allow(Stripe::Customer).to receive(:retrieve).with("cus_real123").and_return(stripe_customer)
  end

  after { ENV.delete("EMAIL"); ENV.delete("USER_ID"); ENV.delete("CONFIRM") }

  it "defaults to a dry run and makes no changes" do
    ENV["USER_ID"] = user.id.to_s

    expect { task.invoke }.to output(/Dry run only/).to_stdout

    expect(user.reload.anonymized_at).to be_present
    expect(user.subscription.reload.stripe_customer_id).to be_nil
  end

  it "restores the user when CONFIRM=yes is set" do
    ENV["USER_ID"] = user.id.to_s
    ENV["CONFIRM"] = "yes"

    task.invoke
    user.reload

    expect(user.anonymized_at).to be_nil
    expect(user.deletion_requested_at).to be_nil
    expect(user.email).to eq("real@example.com")
    expect(user.name).to eq("Real Name")
    expect(user.subscription.reload.stripe_customer_id).to eq("cus_real123")
  end

  it "aborts when the subscription has no stripe_subscription_id" do
    ENV["USER_ID"] = user.id.to_s
    ENV["CONFIRM"] = "yes"
    user.subscription.update!(stripe_subscription_id: nil)

    expect { task.invoke }.to raise_error(SystemExit)
  end
end

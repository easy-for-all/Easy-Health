require "rails_helper"

RSpec.describe StripeCheckoutService do
  describe ".find_or_create_customer" do
    it "reuses a valid Stripe customer id" do
      user = create(:user, paid_plan: true)
      user.subscription.update!(stripe_customer_id: "cus_real123")

      expect(Stripe::Customer).not_to receive(:create)

      expect(described_class.find_or_create_customer(user)).to eq("cus_real123")
    end

    it "creates a new customer when stripe_customer_id is blank" do
      user = create(:user, paid_plan: true)
      fake_customer = double("Stripe::Customer", id: "cus_new123")
      allow(Stripe::Customer).to receive(:create).and_return(fake_customer)

      expect(described_class.find_or_create_customer(user)).to eq("cus_new123")
      expect(user.subscription.reload.stripe_customer_id).to eq("cus_new123")
    end

    it "creates a new customer when stripe_customer_id is not a real Stripe id (e.g. corrupted by account deletion)" do
      user = create(:user, paid_plan: true)
      user.subscription.update!(stripe_customer_id: "deleted_#{user.id}")
      fake_customer = double("Stripe::Customer", id: "cus_fresh456")
      allow(Stripe::Customer).to receive(:create).and_return(fake_customer)

      expect(described_class.find_or_create_customer(user)).to eq("cus_fresh456")
      expect(user.subscription.reload.stripe_customer_id).to eq("cus_fresh456")
    end
  end
end

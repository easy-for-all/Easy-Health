require "rails_helper"

RSpec.describe StripeCheckoutService do
  def stripe_env(overrides = {})
    {
      "STRIPE_SECRET_KEY" => "sk_test_checkout",
      "STRIPE_PRICE_PRO_MONTHLY" => "price_monthly_123",
      "STRIPE_PRICE_PRO_YEARLY" => "price_yearly_123",
      "FRONTEND_URL" => "https://easyhealth.art"
    }.merge(overrides)
  end

  describe ".call" do
    it "returns checkout_url and session_id" do
      user = create(:user, paid_plan: true)
      user.subscription.update!(stripe_customer_id: "cus_real123")
      session = double("Stripe::Checkout::Session", id: "cs_test_123", url: "https://checkout.stripe.com/c/pay")

      with_env(stripe_env) do
        allow(Stripe::Checkout::Session).to receive(:create).and_return(session)

        result = described_class.call(user: user, plan: "pro_yearly")

        expect(result).to eq(checkout_url: "https://checkout.stripe.com/c/pay", session_id: "cs_test_123")
      end
    end

    it "raises a structured configuration error when the secret key is absent" do
      user = create(:user, paid_plan: true)

      with_env(stripe_env("STRIPE_SECRET_KEY" => nil)) do
        expect {
          described_class.call(user: user, plan: "pro_yearly")
        }.to raise_error(StripeCheckoutService::BillingError) { |error|
          expect(error.code).to eq("billing_configuration_error")
          expect(error.public_message).to eq("O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.")
        }
      end
    end

    it "raises a structured configuration error when FRONTEND_URL is absent" do
      user = create(:user, paid_plan: true)
      user.subscription.update!(stripe_customer_id: "cus_real123")

      with_env(stripe_env("FRONTEND_URL" => nil)) do
        expect {
          described_class.call(user: user, plan: "pro_yearly")
        }.to raise_error(StripeCheckoutService::BillingError) { |error|
          expect(error.code).to eq("billing_configuration_error")
          expect(error.public_message).to eq("O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.")
        }
      end
    end
  end

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

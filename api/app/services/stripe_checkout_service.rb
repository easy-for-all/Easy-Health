class StripeCheckoutService
  VALID_PLANS = %w[pro_monthly pro_yearly].freeze

  PRICE_IDS = {
    "pro_monthly" => -> { ENV.fetch("STRIPE_PRICE_PRO_MONTHLY") },
    "pro_yearly"  => -> { ENV.fetch("STRIPE_PRICE_PRO_YEARLY") }
  }.freeze

  def self.call(user:, plan:)
    raise ArgumentError, "Invalid plan: #{plan}" unless VALID_PLANS.include?(plan)

    price_id = PRICE_IDS[plan].call

    customer_id = find_or_create_customer(user)

    session = Stripe::Checkout::Session.create(
      customer: customer_id,
      mode: "subscription",
      allow_promotion_codes: true,
      line_items: [{
        price: price_id,
        quantity: 1
      }],
      subscription_data: {
        trial_period_days: 7,
        metadata: { user_id: user.id.to_s, plan: plan }
      },
      metadata: { user_id: user.id.to_s, plan: plan },
      success_url: "#{ENV.fetch('FRONTEND_URL')}/billing/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{ENV.fetch('FRONTEND_URL')}/billing/cancel"
    )

    session.url
  end

  def self.find_or_create_customer(user)
    sub = user.subscription

    return sub.stripe_customer_id if sub&.stripe_customer_id&.start_with?("cus_")

    customer = Stripe::Customer.create(
      email: user.email,
      name: user.name,
      metadata: { user_id: user.id.to_s }
    )

    if sub
      sub.update!(stripe_customer_id: customer.id)
    else
      user.create_subscription!(
        stripe_customer_id: customer.id,
        plan_name: "pro_monthly",
        status: "incomplete"
      )
    end

    customer.id
  end
end

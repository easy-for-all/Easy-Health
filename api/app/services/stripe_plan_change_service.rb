class StripePlanChangeService
  PRICE_IDS = {
    "pro_monthly" => -> { ENV.fetch("STRIPE_PRICE_PRO_MONTHLY") },
    "pro_yearly"  => -> { ENV.fetch("STRIPE_PRICE_PRO_YEARLY") }
  }.freeze

  def self.call(user:, new_plan:)
    raise ArgumentError, "Invalid plan: #{new_plan}" unless Subscription::VALID_PLANS.include?(new_plan)

    sub = user.subscription
    raise ArgumentError, "No active subscription found" if sub.nil? || sub.stripe_subscription_id.blank?
    raise ArgumentError, "Subscription is not active" unless sub.status.in?(%w[active trialing])

    stripe_sub = Stripe::Subscription.retrieve(sub.stripe_subscription_id)
    item_id = stripe_sub.items.data.first.id
    new_price_id = PRICE_IDS[new_plan].call

    updated = Stripe::Subscription.update(
      stripe_sub.id,
      items: [{ id: item_id, price: new_price_id }],
      proration_behavior: "always_invoice",
      metadata: { user_id: user.id.to_s, plan: new_plan }
    )

    sub.update!(
      plan_name: new_plan,
      stripe_price_id: new_price_id,
      status: updated.status,
      current_period_end: updated.current_period_end ? Time.zone.at(updated.current_period_end) : sub.current_period_end
    )

    sub
  end
end

class StripeSyncService
  Result = Struct.new(:success, :message, :subscription, keyword_init: true)

  def self.call(user:)
    customer_id = user.subscription&.stripe_customer_id

    if customer_id.blank?
      customers = Stripe::Customer.search(query: "email:'#{user.email}'").data
      return Result.new(success: false, message: "No Stripe customer found for #{user.email}") if customers.empty?

      customer_id = customers.first.id
      Rails.logger.info("[StripeSync] found customer #{customer_id} by email for user=#{user.id}")
    end

    stripe_subs = Stripe::Subscription.list(customer: customer_id, limit: 5, expand: ["data.items"]).data

    if stripe_subs.empty?
      return Result.new(success: false, message: "No subscriptions found in Stripe for customer=#{customer_id}")
    end

    # Prefer active/trialing, fallback to most recent
    stripe_sub = stripe_subs.find { |s| s.status.in?(%w[active trialing]) } || stripe_subs.first

    sub = user.subscription || user.build_subscription
    plan_name = Subscription.plan_from_price_id(stripe_sub.items.data.first&.price&.id)

    sub.assign_attributes(
      stripe_customer_id: customer_id,
      stripe_subscription_id: stripe_sub.id,
      stripe_price_id: stripe_sub.items.data.first&.price&.id,
      plan_name: plan_name,
      status: stripe_sub.status,
      current_period_start: stripe_sub.current_period_start ? Time.zone.at(stripe_sub.current_period_start) : nil,
      current_period_end: stripe_sub.current_period_end ? Time.zone.at(stripe_sub.current_period_end) : nil,
      cancel_at_period_end: stripe_sub.cancel_at_period_end,
      trial_end: stripe_sub.trial_end ? Time.zone.at(stripe_sub.trial_end) : nil
    )
    sub.save!

    Rails.logger.info("[StripeSync] synced user=#{user.email} stripe_sub=#{stripe_sub.id} status=#{stripe_sub.status} plan=#{plan_name}")
    Result.new(success: true, message: "Synced: #{plan_name} / #{stripe_sub.status}", subscription: sub)
  rescue Stripe::StripeError => e
    Rails.logger.error("[StripeSync] Stripe error for user=#{user.id}: #{e.message}")
    Result.new(success: false, message: "Stripe error: #{e.message}")
  rescue => e
    Rails.logger.error("[StripeSync] error for user=#{user.id}: #{e.message}")
    Result.new(success: false, message: e.message)
  end
end

class StripeWebhookService
  def self.call(payload:, sig_header:)
    event = Stripe::Webhook.construct_event(
      payload,
      sig_header,
      ENV.fetch("STRIPE_WEBHOOK_SECRET")
    )

    return if already_processed?(event.id, event.type)

    process(event)

    StripeEvent.create!(
      stripe_event_id: event.id,
      event_type: event.type,
      processed_at: Time.current
    )
  end

  def self.already_processed?(event_id, event_type)
    StripeEvent.exists?(stripe_event_id: event_id)
  rescue => e
    Rails.logger.error("StripeWebhookService#already_processed? error: #{e.message}")
    false
  end

  def self.process(event)
    case event.type
    when "checkout.session.completed"
      handle_checkout_completed(event.data.object)
    when "customer.subscription.created", "customer.subscription.updated"
      handle_subscription_upsert(event.data.object)
    when "customer.subscription.deleted"
      handle_subscription_deleted(event.data.object)
    when "invoice.paid"
      handle_invoice_paid(event.data.object)
    when "invoice.payment_failed"
      handle_invoice_payment_failed(event.data.object)
    end
  end

  def self.handle_checkout_completed(session)
    user_id = session.metadata["user_id"]
    return Rails.logger.warn("checkout.session.completed missing user_id") if user_id.blank?

    user = User.find_by(id: user_id)
    return Rails.logger.warn("checkout.session.completed user not found: #{user_id}") unless user

    customer_id     = session.customer
    subscription_id = session.subscription
    plan            = session.metadata["plan"] || "pro_monthly"

    sub = user.subscription || user.build_subscription
    sub.assign_attributes(
      stripe_customer_id: customer_id,
      stripe_subscription_id: subscription_id,
      plan_name: plan,
      status: "incomplete"
    )
    sub.save!
  end

  def self.handle_subscription_upsert(stripe_sub)
    sub = find_or_build_subscription(stripe_sub)
    return unless sub

    plan_name = Subscription.plan_from_price_id(stripe_sub.items.data.first&.price&.id)

    sub.assign_attributes(
      stripe_subscription_id: stripe_sub.id,
      stripe_price_id: stripe_sub.items.data.first&.price&.id,
      plan_name: plan_name,
      status: stripe_sub.status,
      current_period_start: Time.zone.at(stripe_sub.current_period_start),
      current_period_end: Time.zone.at(stripe_sub.current_period_end),
      cancel_at_period_end: stripe_sub.cancel_at_period_end,
      trial_end: stripe_sub.trial_end ? Time.zone.at(stripe_sub.trial_end) : nil
    )
    sub.save!
  end

  def self.handle_subscription_deleted(stripe_sub)
    sub = Subscription.find_by(stripe_subscription_id: stripe_sub.id)
    return unless sub

    sub.update!(status: "canceled", plan_name: "pro_monthly", canceled_at: Time.current)
  end

  def self.handle_invoice_paid(invoice)
    return if invoice.subscription.blank?

    sub = Subscription.find_by(stripe_subscription_id: invoice.subscription)
    sub&.update!(status: "active")
  end

  def self.handle_invoice_payment_failed(invoice)
    return if invoice.subscription.blank?

    sub = Subscription.find_by(stripe_subscription_id: invoice.subscription)
    sub&.update!(status: "past_due")
  end

  def self.find_or_build_subscription(stripe_sub)
    user_id = stripe_sub.metadata["user_id"]

    sub = Subscription.find_by(stripe_subscription_id: stripe_sub.id)
    return sub if sub

    if user_id.present?
      user = User.find_by(id: user_id)
      return user&.subscription || user&.build_subscription
    end

    customer_id = stripe_sub.customer
    Subscription.find_by(stripe_customer_id: customer_id)
  end
end

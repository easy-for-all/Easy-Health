class StripeWebhookService
  SETTLED_STATUSES = %w[trialing active past_due].freeze

  def self.call(payload:, sig_header:)
    event = Stripe::Webhook.construct_event(
      payload,
      sig_header,
      ENV.fetch("STRIPE_WEBHOOK_SECRET")
    )

    return if already_processed?(event.id, event.type)

    Rails.logger.info("[Stripe] processing event=#{event.type} id=#{event.id}")
    process(event)

    StripeEvent.create!(
      stripe_event_id: event.id,
      event_type: event.type,
      processed_at: Time.current
    )
    Rails.logger.info("[Stripe] done event=#{event.type} id=#{event.id}")
  end

  def self.already_processed?(event_id, event_type)
    StripeEvent.exists?(stripe_event_id: event_id)
  rescue => e
    Rails.logger.error("[Stripe] already_processed? error: #{e.message}")
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
    else
      Rails.logger.info("[Stripe] unhandled event type=#{event.type}")
    end
  end

  def self.handle_checkout_completed(session)
    user_id = session.metadata["user_id"]
    unless user_id.present?
      Rails.logger.warn("[Stripe] checkout.session.completed missing user_id session=#{session.id}")
      return
    end

    user = User.find_by(id: user_id)
    unless user
      Rails.logger.warn("[Stripe] checkout.session.completed user not found user_id=#{user_id}")
      return
    end

    customer_id     = session.customer
    subscription_id = session.subscription
    plan            = session.metadata["plan"] || "pro_monthly"

    sub = user.subscription || user.build_subscription

    attrs = {
      stripe_customer_id: customer_id,
      stripe_subscription_id: subscription_id,
      plan_name: plan
    }

    # Avoid overwriting a status already set by an earlier subscription webhook
    # (race condition: subscription.created can arrive before checkout.session.completed)
    attrs[:status] = "incomplete" unless sub.persisted? && SETTLED_STATUSES.include?(sub.status)

    sub.assign_attributes(attrs)
    sub.save!

    Rails.logger.info("[Stripe] checkout completed user=#{user.email} sub=#{subscription_id} status=#{sub.status}")
  end

  def self.handle_subscription_upsert(stripe_sub)
    sub = find_or_build_subscription(stripe_sub)
    unless sub
      Rails.logger.warn("[Stripe] subscription_upsert could not find/build sub for stripe_sub=#{stripe_sub.id} customer=#{stripe_sub.customer}")
      return
    end

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

    Rails.logger.info("[Stripe] subscription upsert stripe_sub=#{stripe_sub.id} status=#{stripe_sub.status} plan=#{plan_name}")
  end

  def self.handle_subscription_deleted(stripe_sub)
    sub = Subscription.find_by(stripe_subscription_id: stripe_sub.id)
    unless sub
      Rails.logger.warn("[Stripe] subscription_deleted not found stripe_sub=#{stripe_sub.id}")
      return
    end

    sub.update!(status: "canceled", canceled_at: Time.current)
    Rails.logger.info("[Stripe] subscription canceled stripe_sub=#{stripe_sub.id}")
  end

  def self.handle_invoice_paid(invoice)
    return if invoice.subscription.blank?

    sub = Subscription.find_by(stripe_subscription_id: invoice.subscription)
    unless sub
      Rails.logger.warn("[Stripe] invoice.paid subscription not found stripe_sub=#{invoice.subscription}")
      return
    end

    sub.update!(status: "active", current_period_end: invoice.period_end ? Time.zone.at(invoice.period_end) : sub.current_period_end)
    Rails.logger.info("[Stripe] invoice paid stripe_sub=#{invoice.subscription} → active")
  end

  def self.handle_invoice_payment_failed(invoice)
    return if invoice.subscription.blank?

    sub = Subscription.find_by(stripe_subscription_id: invoice.subscription)
    unless sub
      Rails.logger.warn("[Stripe] invoice.payment_failed subscription not found stripe_sub=#{invoice.subscription}")
      return
    end

    sub.update!(status: "past_due")
    Rails.logger.info("[Stripe] invoice payment failed stripe_sub=#{invoice.subscription} → past_due")
  end

  def self.find_or_build_subscription(stripe_sub)
    # 1. Match by stripe subscription ID (most reliable)
    sub = Subscription.find_by(stripe_subscription_id: stripe_sub.id)
    return sub if sub

    # 2. Match by user_id from subscription metadata (set via subscription_data.metadata in checkout)
    user_id = stripe_sub.metadata["user_id"]
    if user_id.present?
      user = User.find_by(id: user_id)
      if user
        Rails.logger.info("[Stripe] find_or_build_subscription matched user_id=#{user_id} from metadata")
        return user.subscription || user.build_subscription
      end
    end

    # 3. Fallback: match by customer ID already in our DB
    customer_id = stripe_sub.customer
    sub = Subscription.find_by(stripe_customer_id: customer_id)
    Rails.logger.info("[Stripe] find_or_build_subscription #{sub ? 'found' : 'NOT found'} by customer=#{customer_id}") unless sub
    sub
  end
end

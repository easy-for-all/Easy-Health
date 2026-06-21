class StripeWebhookService
  SETTLED_STATUSES = %w[trialing active past_due].freeze

  def self.call(payload:, sig_header:, secret:)
    event = Stripe::Webhook.construct_event(payload, sig_header, secret)

    Rails.logger.info("[Stripe] received event=#{event.type} id=#{event.id}")

    stripe_event_record = begin
      StripeEvent.create!(
        stripe_event_id: event.id,
        event_type:      event.type,
        processed_at:    Time.current,
        status:          "processing"
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      Rails.logger.info("[Stripe] duplicate event id=#{event.id}, skipping")
      return
    end

    begin
      process(event)
      stripe_event_record.update_columns(status: "processed")
      Rails.logger.info("[Stripe] done event=#{event.type} id=#{event.id}")
    rescue => e
      stripe_event_record.update_columns(status: "failed", error_message: e.message)
      Rails.logger.error("[Stripe] processing failed event=#{event.type} id=#{event.id}: #{e.class}: #{e.message}")
      raise
    end
  end

  def self.process(event)
    case event.type
    when "checkout.session.completed"
      handle_checkout_completed(event.data.object)
    when "customer.subscription.created", "customer.subscription.updated"
      handle_subscription_upsert(event.data.object)
    when "customer.subscription.deleted"
      handle_subscription_deleted(event.data.object)
    when "invoice.paid", "invoice.payment_succeeded"
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

    item      = stripe_sub.items.data.first
    plan_name = Subscription.plan_from_price_id(item&.price&.id)

    sub.assign_attributes(
      stripe_subscription_id: stripe_sub.id,
      stripe_price_id:        item&.price&.id,
      plan_name:              plan_name,
      status:                 stripe_sub.status,
      current_period_start:   item&.current_period_start ? Time.zone.at(item.current_period_start) : nil,
      current_period_end:     item&.current_period_end   ? Time.zone.at(item.current_period_end)   : nil,
      cancel_at_period_end:   stripe_sub.cancel_at_period_end,
      trial_end:              stripe_sub.trial_end ? Time.zone.at(stripe_sub.trial_end) : nil
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
    subscription_id = invoice.parent&.subscription_details&.subscription
    return if subscription_id.blank?

    sub = Subscription.find_by(stripe_subscription_id: subscription_id)
    unless sub
      Rails.logger.warn("[Stripe] invoice.paid subscription not found stripe_sub=#{subscription_id}")
      return
    end

    period_end = invoice.lines&.data&.first&.period&.end
    was_inactive = !sub.subscription_active?
    sub.update!(
      status:             "active",
      current_period_end: period_end ? Time.zone.at(period_end) : sub.current_period_end
    )
    Rails.logger.info("[Stripe] invoice paid stripe_sub=#{subscription_id} → active")
    UserEventService.track(user: sub.user, event: :subscription_created) if was_inactive
  end

  def self.handle_invoice_payment_failed(invoice)
    subscription_id = invoice.parent&.subscription_details&.subscription
    return if subscription_id.blank?

    sub = Subscription.find_by(stripe_subscription_id: subscription_id)
    unless sub
      Rails.logger.warn("[Stripe] invoice.payment_failed subscription not found stripe_sub=#{subscription_id}")
      return
    end

    sub.update!(status: "past_due")
    Rails.logger.info("[Stripe] invoice payment failed stripe_sub=#{subscription_id} → past_due")
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

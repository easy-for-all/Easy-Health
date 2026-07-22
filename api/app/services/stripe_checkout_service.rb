class StripeCheckoutService
  VALID_PLANS = %w[pro_monthly pro_yearly].freeze

  PLAN_PRICE_ENV = {
    "pro_monthly" => "STRIPE_PRICE_PRO_MONTHLY",
    "pro_yearly"  => "STRIPE_PRICE_PRO_YEARLY"
  }.freeze

  class BillingError < StandardError
    attr_reader :code, :public_message, :status, :details

    def initialize(code:, public_message:, status:, details: {})
      super(public_message)
      @code = code
      @public_message = public_message
      @status = status
      @details = details
    end
  end

  def self.call(user:, plan:, request_id: nil, platform: nil)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    validate_plan!(plan)
    configure_stripe!

    price_id = price_id_for(plan)
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
      success_url: "#{frontend_url}/billing/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{frontend_url}/billing/cancel"
    )

    log_checkout(
      request_id: request_id,
      user_id: user.id,
      plan: plan,
      price_alias: PLAN_PRICE_ENV[plan],
      platform: platform,
      stage: "checkout_session",
      result: "success",
      duration_ms: duration_ms(started_at),
      stripe_request_id: stripe_request_id(session)
    )

    { checkout_url: session.url, session_id: session.id }
  rescue BillingError => e
    log_checkout(
      request_id: request_id,
      user_id: user&.id,
      plan: plan,
      price_alias: PLAN_PRICE_ENV[plan],
      platform: platform,
      stage: "checkout_session",
      result: "failure",
      duration_ms: duration_ms(started_at),
      exception_class: e.class.name,
      error_code: e.code
    )
    raise
  rescue Stripe::APIConnectionError, Stripe::APIError, Stripe::RateLimitError => e
    error = billing_error(
      code: "billing_stripe_unavailable",
      public_message: "O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.",
      status: :service_unavailable,
      details: { stripe_request_id: e.respond_to?(:request_id) ? e.request_id : nil }
    )
    log_checkout(
      request_id: request_id,
      user_id: user&.id,
      plan: plan,
      price_alias: PLAN_PRICE_ENV[plan],
      platform: platform,
      stage: "checkout_session",
      result: "failure",
      duration_ms: duration_ms(started_at),
      exception_class: e.class.name,
      error_code: error.code
    )
    raise error
  rescue Stripe::StripeError => e
    error = billing_error(
      code: "billing_checkout_creation_failed",
      public_message: "Não foi possível iniciar o checkout.",
      status: :bad_gateway,
      details: { stripe_request_id: e.respond_to?(:request_id) ? e.request_id : nil }
    )
    log_checkout(
      request_id: request_id,
      user_id: user&.id,
      plan: plan,
      price_alias: PLAN_PRICE_ENV[plan],
      platform: platform,
      stage: "checkout_session",
      result: "failure",
      duration_ms: duration_ms(started_at),
      exception_class: e.class.name,
      error_code: error.code
    )
    raise error
  end

  def self.find_or_create_customer(user)
    sub = user.subscription

    return sub.stripe_customer_id if sub&.stripe_customer_id&.start_with?("cus_")

    customer = create_customer(user)

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

  def self.validate_plan!(plan)
    return if VALID_PLANS.include?(plan)

    raise billing_error(
      code: "billing_invalid_plan",
      public_message: "Este plano não está disponível no momento.",
      status: :unprocessable_entity
    )
  end

  def self.configure_stripe!
    secret = ENV["STRIPE_SECRET_KEY"].to_s
    return Stripe.api_key = secret if valid_secret_key?(secret)

    raise billing_error(
      code: "billing_configuration_error",
      public_message: "O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.",
      status: :service_unavailable,
      details: { missing: "STRIPE_SECRET_KEY" }
    )
  end

  def self.price_id_for(plan)
    env_key = PLAN_PRICE_ENV[plan]
    price_id = ENV[env_key].to_s
    return price_id if price_id.start_with?("price_")

    raise billing_error(
      code: "billing_configuration_error",
      public_message: "O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.",
      status: :service_unavailable,
      details: { missing: env_key }
    )
  end

  def self.frontend_url
    value = ENV["FRONTEND_URL"].to_s
    return value.delete_suffix("/") if value.start_with?("https://", "http://")

    raise billing_error(
      code: "billing_configuration_error",
      public_message: "O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.",
      status: :service_unavailable,
      details: { missing: "FRONTEND_URL" }
    )
  end

  def self.create_customer(user)
    Stripe::Customer.create(
      email: user.email,
      name: user.name,
      metadata: { user_id: user.id.to_s }
    )
  rescue Stripe::APIConnectionError, Stripe::APIError, Stripe::RateLimitError => e
    raise billing_error(
      code: "billing_stripe_unavailable",
      public_message: "O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.",
      status: :service_unavailable,
      details: { stripe_request_id: e.respond_to?(:request_id) ? e.request_id : nil }
    )
  rescue Stripe::StripeError => e
    raise billing_error(
      code: "billing_customer_error",
      public_message: "Não foi possível iniciar o checkout.",
      status: :bad_gateway,
      details: { stripe_request_id: e.respond_to?(:request_id) ? e.request_id : nil }
    )
  end

  def self.valid_secret_key?(value)
    value.start_with?("sk_test_", "sk_live_", "rk_test_", "rk_live_")
  end

  def self.billing_error(code:, public_message:, status:, details: {})
    BillingError.new(code: code, public_message: public_message, status: status, details: details.compact)
  end

  def self.duration_ms(started_at)
    return nil unless started_at

    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end

  def self.stripe_request_id(session)
    session.respond_to?(:last_response) ? session.last_response&.request_id : nil
  end

  def self.log_checkout(payload)
    Rails.logger.info("[BillingCheckout] #{payload.compact.to_json}")
  end
end

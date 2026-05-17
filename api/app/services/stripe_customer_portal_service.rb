class StripeCustomerPortalService
  def self.call(user:)
    customer_id = user.subscription&.stripe_customer_id
    raise ArgumentError, "No Stripe customer found for user" if customer_id.blank?

    session = Stripe::BillingPortal::Session.create(
      customer: customer_id,
      return_url: "#{ENV.fetch('FRONTEND_URL')}/billing"
    )

    session.url
  end
end

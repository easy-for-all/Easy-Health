Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY", nil)

# Fail fast on Stripe network issues so a hung request surfaces as a handled
# 503 (billing_stripe_unavailable, with CORS headers) instead of a bare 502
# from the reverse proxy. read_timeout stays comfortably below the proxy timeout.
Stripe.open_timeout = Integer(ENV.fetch("STRIPE_OPEN_TIMEOUT", "5"))
Stripe.read_timeout = Integer(ENV.fetch("STRIPE_READ_TIMEOUT", "15"))
Stripe.max_network_retries = Integer(ENV.fetch("STRIPE_MAX_NETWORK_RETRIES", "2"))

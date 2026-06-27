#!/usr/bin/env ruby
# Provisions EasyHealth Pro product, prices, and webhook on a Stripe account.
# Usage: STRIPE_SETUP_KEY=rk_live_... ruby scripts/setup_easyhealth_stripe.rb
#
# Idempotent: re-runs safely; finds existing resources before creating new ones.
# NEVER commit STRIPE_SETUP_KEY. This script reads it only from ENV.

require "bundler/setup"
require "stripe"

STRIPE_SETUP_KEY = ENV.fetch("STRIPE_SETUP_KEY") { abort "[ERROR] STRIPE_SETUP_KEY env var is not set." }
Stripe.api_key = STRIPE_SETUP_KEY

PRODUCT_NAME   = "EasyHealth Pro"
WEBHOOK_URL    = "https://easyhealth.art/api/v1/webhooks/stripe"
WEBHOOK_EVENTS = %w[
  checkout.session.completed
  customer.subscription.created
  customer.subscription.updated
  customer.subscription.deleted
  invoice.paid
  invoice.payment_failed
].freeze
MONTHLY_AMOUNT = 1990   # BRL cents — R$ 19,90
YEARLY_AMOUNT  = 11880  # BRL cents — R$ 118,80

def mask(value, visible_suffix: 8)
  return "(nil)" if value.nil?
  prefix = value[0, 12]
  suffix = value[-visible_suffix..]
  "#{prefix}...#{suffix}"
end

def step(label)
  puts "\n[#{label}]"
  yield
rescue Stripe::AuthenticationError => e
  abort "[AUTH ERROR] #{e.message}\nCheck that STRIPE_SETUP_KEY is valid and has the required permissions."
rescue Stripe::PermissionError => e
  puts "[PERMISSION DENIED] #{e.message}"
  nil
rescue Stripe::StripeError => e
  puts "[STRIPE ERROR] #{e.message}"
  nil
end

# ---------------------------------------------------------------------------
# 1. Product
# ---------------------------------------------------------------------------
product = step("Product") do
  existing = Stripe::Product.list(active: true, limit: 100).data
                            .find { |p| p.name == PRODUCT_NAME }
  if existing
    puts "  Found existing product: #{existing.id}"
    existing
  else
    created = Stripe::Product.create(
      name: PRODUCT_NAME,
      metadata: { app: "easyhealth" }
    )
    puts "  Created product: #{created.id}"
    created
  end
end

abort "[FATAL] Could not obtain product." unless product

# ---------------------------------------------------------------------------
# 2. Monthly price — R$ 19,90 / month
# ---------------------------------------------------------------------------
price_monthly = step("Monthly Price (BRL 19,90/month)") do
  existing = Stripe::Price.list(product: product.id, currency: "brl", active: true, limit: 100).data
                          .find { |p| p.unit_amount == MONTHLY_AMOUNT && p.recurring&.interval == "month" }
  if existing
    puts "  Found existing monthly price: #{existing.id}"
    existing
  else
    created = Stripe::Price.create(
      product: product.id,
      currency: "brl",
      unit_amount: MONTHLY_AMOUNT,
      recurring: { interval: "month" },
      nickname: "EasyHealth Pro Monthly"
    )
    puts "  Created monthly price: #{created.id}"
    created
  end
end

# ---------------------------------------------------------------------------
# 3. Yearly price — R$ 118,80 / year
# ---------------------------------------------------------------------------
price_yearly = step("Yearly Price (BRL 118,80/year)") do
  existing = Stripe::Price.list(product: product.id, currency: "brl", active: true, limit: 100).data
                          .find { |p| p.unit_amount == YEARLY_AMOUNT && p.recurring&.interval == "year" }
  if existing
    puts "  Found existing yearly price: #{existing.id}"
    existing
  else
    created = Stripe::Price.create(
      product: product.id,
      currency: "brl",
      unit_amount: YEARLY_AMOUNT,
      recurring: { interval: "year" },
      nickname: "EasyHealth Pro Yearly"
    )
    puts "  Created yearly price: #{created.id}"
    created
  end
end

# ---------------------------------------------------------------------------
# 4. Webhook endpoint
# ---------------------------------------------------------------------------
webhook_secret = nil
webhook = step("Webhook Endpoint") do
  existing = Stripe::WebhookEndpoint.list(limit: 100).data
                                    .find { |w| w.url == WEBHOOK_URL && w.status == "enabled" }
  if existing
    puts "  Found existing webhook: #{existing.id}"
    puts "  NOTE: Signing secret is only shown at creation time."
    puts "  If you need it, roll it in the Stripe dashboard and update STRIPE_WEBHOOK_SECRET."
    existing
  else
    created = Stripe::WebhookEndpoint.create(
      url: WEBHOOK_URL,
      enabled_events: WEBHOOK_EVENTS,
      description: "EasyHealth production webhook"
    )
    webhook_secret = created.secret
    puts "  Created webhook: #{created.id}"
    created
  end
end

# ---------------------------------------------------------------------------
# 5. Output
# ---------------------------------------------------------------------------
puts "\n" + ("=" * 60)
puts "RESULTADO — copie os valores abaixo para o .env de produção"
puts "=" * 60

puts <<~ENV

  # Stripe nova conta — obtenha a secret key no dashboard:
  # https://dashboard.stripe.com/apikeys → Secret key (Reveal)
  STRIPE_SECRET_KEY=sk_live_51TjVZt...(obter no dashboard)

ENV

if webhook_secret
  puts "  STRIPE_WEBHOOK_SECRET=#{mask(webhook_secret)}"
  puts "  (valor completo exibido apenas uma vez — guarde agora)"
  puts "\n  Valor COMPLETO do STRIPE_WEBHOOK_SECRET:"
  puts "  #{webhook_secret}"
else
  puts "  STRIPE_WEBHOOK_SECRET=(webhook já existia — secret não disponível aqui)"
  puts "  Acesse: Dashboard → Developers → Webhooks → #{WEBHOOK_URL} → Signing secret"
end

puts "\n  STRIPE_PRICE_PRO_MONTHLY=#{price_monthly&.id || "(erro — verificar acima)"}"
puts "  STRIPE_PRICE_PRO_YEARLY=#{price_yearly&.id || "(erro — verificar acima)"}"

puts "\n" + ("=" * 60)
puts "Verifique em: https://dashboard.stripe.com/products"
puts "              https://dashboard.stripe.com/webhooks"

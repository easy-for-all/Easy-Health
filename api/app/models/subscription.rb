class Subscription < ApplicationRecord
  belongs_to :user

  VALID_PLANS = %w[pro_monthly pro_yearly].freeze
  VALID_STATUSES = %w[trialing active past_due canceled unpaid incomplete].freeze

  validates :plan_name, inclusion: { in: VALID_PLANS }
  validates :status, inclusion: { in: VALID_STATUSES }

  def self.plan_from_price_id(price_id)
    case price_id
    when ENV["STRIPE_PRICE_PRO_MONTHLY"] then "pro_monthly"
    when ENV["STRIPE_PRICE_PRO_YEARLY"]  then "pro_yearly"
    else "pro_monthly"
    end
  end

  def pro_monthly?        = plan_name == "pro_monthly"
  def pro_yearly?         = plan_name == "pro_yearly"
  def pro?                = pro_monthly? || pro_yearly?
  def subscription_active? = status.in?(%w[active trialing])
  def paid_plan?          = subscription_active? && pro?
  def billing_required?   = !paid_plan?

  def billing_status
    {
      plan: plan_name,
      status: status,
      paid: paid_plan?,
      trial_end: trial_end,
      current_period_end: current_period_end,
      cancel_at_period_end: cancel_at_period_end,
      stripe_customer_id: stripe_customer_id
    }
  end
end

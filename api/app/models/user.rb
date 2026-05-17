class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_one :health_profile, dependent: :destroy
  has_many :workout_plans, dependent: :destroy
  has_many :workout_sessions, dependent: :destroy
  has_many :user_media, class_name: "UserMedia", dependent: :destroy
  has_one_attached :avatar
  has_one :subscription, dependent: :destroy

  delegate :pro_monthly?, :pro_yearly?, :pro?, :paid_plan?,
           :subscription_active?, :billing_required?,
           to: :subscription, allow_nil: true

  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  def active_workout_plan
    workout_plans.active.first
  end

  def no_plan?
    subscription.nil? || subscription.billing_required?
  end

  def billing_status
    subscription&.billing_status || {
      plan: "none",
      status: "none",
      paid: false,
      trial_end: nil,
      current_period_end: nil,
      cancel_at_period_end: false,
      stripe_customer_id: nil
    }
  end
end

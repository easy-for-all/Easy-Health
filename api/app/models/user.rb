class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_one :health_profile, dependent: :destroy
  has_many :workout_plans, dependent: :destroy
  has_many :workout_sessions, dependent: :destroy
  has_many :user_favorite_exercises, dependent: :destroy
  has_many :favorite_exercises, through: :user_favorite_exercises, source: :exercise
  has_many :user_media, class_name: "UserMedia", dependent: :destroy
  has_many :health_data_points, dependent: :destroy
  has_many :ai_usage_logs, dependent: :destroy
  has_one_attached :avatar
  has_one :subscription, dependent: :destroy

  delegate :pro_monthly?, :pro_yearly?, :pro?, :subscription_active?,
           to: :subscription, allow_nil: true

  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  def active_workout_plan
    workout_plans.active.first
  end

  def paid_plan?
    return true if admin?
    subscription&.paid_plan? || false
  end

  def billing_required?
    return false if admin?
    subscription.nil? || subscription.billing_required?
  end

  def no_plan?
    return false if admin?
    subscription.nil? || subscription.billing_required?
  end

  def can_access_workout?
    return true if admin?
    return true if paid_plan?
    !free_workout_used?
  end

  def billing_status
    if admin?
      return {
        plan: "admin",
        status: "active",
        paid: true,
        trial_end: nil,
        current_period_end: nil,
        cancel_at_period_end: false,
        stripe_customer_id: nil,
        free_workout_used: free_workout_used
      }
    end
    base = subscription&.billing_status || {
      plan: "none",
      status: "none",
      paid: false,
      trial_end: nil,
      current_period_end: nil,
      cancel_at_period_end: false,
      stripe_customer_id: nil
    }
    base.merge(free_workout_used: free_workout_used)
  end
end

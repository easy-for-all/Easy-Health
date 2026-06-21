class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  ACCOUNT_TYPES = %w[regular personal_trainer].freeze
  PROFILE_VISIBILITIES = %w[private public_limited public].freeze
  TRIAL_DURATION_DAYS = 7

  has_one :health_profile, dependent: :destroy
  has_many :workout_plans, dependent: :destroy
  has_many :workout_sessions, dependent: :destroy
  has_many :user_favorite_exercises, dependent: :destroy
  has_many :favorite_exercises, through: :user_favorite_exercises, source: :exercise
  has_many :user_media, class_name: "UserMedia", dependent: :destroy
  has_many :health_data_points, dependent: :destroy
  has_many :ai_usage_logs, dependent: :destroy
  has_many :ai_training_decision_logs, dependent: :destroy
  has_many :ai_chat_messages, dependent: :destroy
  has_many :user_training_preferences, dependent: :destroy
  has_many :exercise_suggestion_logs, dependent: :destroy
  has_one_attached :avatar
  has_one :subscription, dependent: :destroy
  has_one :public_profile, dependent: :destroy
  has_many :shared_workouts, foreign_key: :owner_id, dependent: :destroy
  has_many :user_events, dependent: :destroy

  # Personal trainer associations
  has_many :personal_client_relationships,
           foreign_key: :personal_id,
           class_name: "PersonalClientRelationship",
           dependent: :destroy
  has_many :clients,
           through: :personal_client_relationships,
           source: :client

  # Client associations
  has_many :trainer_client_relationships,
           foreign_key: :client_id,
           class_name: "PersonalClientRelationship",
           dependent: :destroy
  has_many :personal_trainers,
           through: :trainer_client_relationships,
           source: :personal

  after_create :create_public_profile_record
  after_create :generate_referral_code
  after_create :start_app_trial

  delegate :pro_monthly?, :pro_yearly?, :pro?, :subscription_active?,
           to: :subscription, allow_nil: true

  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :account_type, inclusion: { in: ACCOUNT_TYPES }
  validates :profile_visibility, inclusion: { in: PROFILE_VISIBILITIES }

  def self.from_omniauth(auth)
    user = find_by(provider: auth.provider, uid: auth.uid)
    user ||= find_by(email: auth.info.email)

    if user
      user.update(provider: auth.provider, uid: auth.uid) unless user.provider.present?
    else
      user = create!(
        provider: auth.provider,
        uid: auth.uid,
        email: auth.info.email,
        name: auth.info.name.presence || auth.info.email.split("@").first,
        password: Devise.friendly_token[0, 20]
      )
    end

    attach_google_avatar(user, auth.info.image) if auth.info.image.present? && !user.avatar.attached?

    user
  end

  def self.attach_google_avatar(user, image_url)
    require "open-uri"
    url = image_url.gsub(/=s\d+-c$/, "=s400-c")
    io  = URI.open(url)  # rubocop:disable Security/Open
    user.avatar.attach(io: io, filename: "google_avatar_#{user.id}.jpg", content_type: "image/jpeg")
  rescue => e
    Rails.logger.warn("[GoogleAvatar] Failed to attach avatar for user #{user.id}: #{e.message}")
  end

  def password_required?
    super && provider.blank?
  end

  def personal_trainer?
    account_type == "personal_trainer"
  end

  def profile_public?
    profile_visibility.in?(%w[public public_limited])
  end

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

  # App-level trial (no Stripe required)
  def trial_active?
    return false if trial_ends_at.nil?
    trial_ends_at > Time.current
  end

  def trial_expired?
    trial_ends_at.present? && trial_ends_at <= Time.current
  end

  def trial_days_remaining
    return 0 unless trial_active?
    [(trial_ends_at - Time.current) / 1.day, 0].max.ceil
  end

  # Stripe subscription active (includes Stripe trialing)
  def premium_active?
    return true if admin?
    subscription&.paid_plan? || false
  end

  def has_active_access?
    premium_active? || trial_active?
  end

  def access_locked?
    !has_active_access?
  end

  def can_access_workout?
    has_active_access?
  end

  private

  def start_app_trial
    return if trial_started_at.present?
    update_columns(
      trial_started_at: created_at,
      trial_ends_at: created_at + TRIAL_DURATION_DAYS.days
    )
    UserEventService.track(user: self, event: :trial_started)
    UserEventService.track(user: self, event: :signup_completed)
  end

  def create_public_profile_record
    create_public_profile(display_name: name)
  end

  def generate_referral_code
    loop do
      code = SecureRandom.alphanumeric(8).upcase
      unless User.exists?(referral_code: code)
        update_column(:referral_code, code)
        break
      end
    end
  end

  public

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
        free_workout_used: free_workout_used,
        app_trial_active: false,
        app_trial_ends_at: nil,
        app_trial_days_remaining: 0,
        access_locked: false
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
    base.merge(
      free_workout_used: free_workout_used,
      app_trial_active: trial_active?,
      app_trial_ends_at: trial_ends_at&.iso8601,
      app_trial_days_remaining: trial_days_remaining,
      access_locked: access_locked?
    )
  end
end

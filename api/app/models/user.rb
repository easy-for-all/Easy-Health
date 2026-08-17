class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:google_oauth2, :google_oauth2_mobile]

  ACCOUNT_TYPES = %w[regular personal_trainer].freeze
  PROFILE_VISIBILITIES = %w[private public_limited public].freeze
  TRIAL_DURATION_DAYS = 7

  # Platform observed at account creation. Reuses the canonical platform
  # allow-list so this never becomes a second, drifting vocabulary.
  SIGNUP_SOURCES = Analytics::EventCatalog::PLATFORMS

  # Current legal document versions. The backend is the source of truth for
  # these — the client only sends acceptance booleans, and we stamp the version
  # here so the two can never drift.
  CURRENT_TERMS_VERSION = "1.0".freeze
  CURRENT_PRIVACY_POLICY_VERSION = "1.0".freeze

  has_one :health_profile, dependent: :destroy
  has_one :fitness_profile, dependent: :destroy
  has_many :workout_plans, dependent: :destroy
  has_many :workout_strategies, dependent: :destroy
  has_many :workout_sessions, dependent: :destroy
  has_many :user_favorite_exercises, dependent: :destroy
  has_many :favorite_exercises, through: :user_favorite_exercises, source: :exercise
  has_many :user_media, class_name: "UserMedia", dependent: :destroy
  has_many :health_data_points, dependent: :destroy
  has_many :ai_usage_logs, dependent: :destroy
  has_many :ai_training_decision_logs, dependent: :destroy
  has_many :coach_insights, dependent: :destroy
  has_many :coach_recommendations, dependent: :destroy
  has_many :user_training_preferences, dependent: :destroy
  has_many :exercise_suggestion_logs, dependent: :destroy
  has_one_attached :avatar
  has_one :subscription, dependent: :destroy
  has_one :public_profile, dependent: :destroy
  has_many :shared_workouts, foreign_key: :owner_id, dependent: :destroy
  has_many :user_events, dependent: :destroy
  has_many :user_segments, dependent: :destroy
  has_many :user_badges, dependent: :destroy
  has_many :community_posts, dependent: :destroy
  has_many :community_reactions, dependent: :destroy
  has_many :community_comments, dependent: :destroy
  has_one  :trainer_profile, dependent: :destroy
  has_many :mobile_auth_codes, dependent: :destroy
  has_many :mobile_sessions, dependent: :destroy
  has_many :personal_notes_as_trainer, class_name: "PersonalNote", foreign_key: :personal_id, dependent: :destroy
  has_many :personal_notes_as_client,  class_name: "PersonalNote", foreign_key: :client_id,   dependent: :destroy

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
  has_many :device_tokens, dependent: :destroy
  has_one :notification_preferences, class_name: "UserNotificationPreferences", dependent: :destroy
  has_many :notification_deliveries, dependent: :destroy

  after_create :create_public_profile_record
  after_create :generate_referral_code
  after_create :start_app_trial

  delegate :pro_monthly?, :pro_yearly?, :pro?, :subscription_active?,
           to: :subscription, allow_nil: true

  # Analytics reporting base: external acquisition only, so every Admin metric
  # shares one denominator.
  #
  # Who counts as internal/automated is decided in ONE place
  # (Analytics::AccountClassification) rather than re-derived here. This scope
  # used to know only about ANALYTICS_INTERNAL_EMAIL_DOMAINS, which meant Google
  # Play's pre-launch robot (@cloudtestlabaccounts.com) was counted as real
  # acquisition — the accounts behind "this release converted 2/2".
  scope :reportable, lambda {
    Analytics::AccountClassification.exclude_non_external(
      where(anonymized_at: nil).where(deletion_requested_at: nil)
    )
  }

  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :account_type, inclusion: { in: ACCOUNT_TYPES }
  validates :profile_visibility, inclusion: { in: PROFILE_VISIBILITIES }
  validate :email_not_blocked, on: :create

  # Fail-open by construction: signup_source is a diagnostic dimension and must
  # NEVER be able to stop an account from being created. An unknown, blank or
  # explicitly nil value (which would violate null: false and turn a signup into
  # a 500) becomes "unknown". That makes the inclusion validation below
  # unreachable on the normal path — it exists as a net for a direct console
  # write. Do not replace this with a strict validation: a malformed client
  # header would then turn into a 422 on sign-up.
  before_validation :normalize_signup_source, on: :create
  validates :signup_source, inclusion: { in: SIGNUP_SOURCES }

  def active_for_authentication?
    super && anonymized_at.nil?
  end

  def inactive_message
    anonymized_at.present? ? :account_deleted : super
  end

  class BlockedEmailError < StandardError; end
  # Raised when a social sign-in would CREATE a new account but the required
  # Terms of Use / Privacy Policy consent was not provided. Existing users
  # authenticate normally and never trigger this.
  class ConsentRequiredError < StandardError; end

  # Did THIS request create the account? Set by from_omniauth at the exact point
  # where it decides to create rather than reuse, so callers never have to guess
  # from the account's age.
  #
  # Not `previously_new_record?`: from_omniauth attaches the Google avatar right
  # after create!, and that second save flips the flag back to false — which is
  # precisely the kind of accident this attribute exists to avoid.
  attr_accessor :newly_registered

  def newly_registered?
    newly_registered == true
  end

  # Finds or provisions a user from an OmniAuth hash. Creating a brand-new
  # account requires that the caller pass the required legal consent; existing
  # users log in normally and their acceptance timestamps are never overwritten.
  #
  # `consent` is a hash with (optional) keys: :terms_accepted, :privacy_accepted,
  # :marketing_consent, :source. Only consulted on the create path.
  #
  # `signup_source` is likewise create-only: an existing user signing in again
  # must never have the origin of their ORIGINAL signup reclassified.
  def self.from_omniauth(auth, consent: {}, signup_source: nil)
    user = find_by(provider: auth.provider, uid: auth.uid)
    user ||= find_by(email: auth.info.email)

    if user
      # An account that already existed and merely gained a Google identity is
      # NOT a registration.
      user.newly_registered = false
      user.update(provider: auth.provider, uid: auth.uid) unless user.provider.present?
    else
      raise BlockedEmailError if BlockedEmail.blocked?(auth.info.email)
      raise ConsentRequiredError unless required_consent_given?(consent)

      user = create!(
        {
          provider: auth.provider,
          uid: auth.uid,
          email: auth.info.email,
          name: auth.info.name.presence || auth.info.email.split("@").first,
          password: Devise.friendly_token[0, 20]
        }.merge(consent_attributes(consent))
         # .compact so a nil never overwrites the column default with NULL.
         .merge({ signup_source: signup_source }.compact)
      )
      # Set on the object the caller receives, at the only point in the flow
      # where a User row is actually inserted.
      user.newly_registered = true
    end

    attach_google_avatar(user, auth.info.image) if auth.info.image.present? && !user.avatar.attached?

    user
  end

  # Single normalizer for every consent flag, whatever transport it arrived on
  # (JSON booleans from the native app, "1"/"0" query params from the web flow).
  # Deliberately stricter than ActiveModel::Type::Boolean: consent is an opt-in,
  # so only an explicit affirmative counts and everything else — nil, "0",
  # "false", "yes", junk — is a refusal.
  def self.explicit_true?(value)
    value == true || value.to_s == "1" || value.to_s.casecmp("true").zero?
  end

  # True only when BOTH Terms of Use and Privacy Policy were accepted. The
  # sign-up screen uses a single checkbox covering both, so callers may pass the
  # same flag for each.
  def self.required_consent_given?(consent)
    explicit_true?(consent[:terms_accepted]) && explicit_true?(consent[:privacy_accepted])
  end

  # Consent columns to stamp on a newly created account. Timestamps/versions are
  # authoritative on the server. marketing_consent is never inferred: an absent
  # or unchecked flag stays false, matching the column default.
  def self.consent_attributes(consent)
    now = Time.current
    {
      terms_accepted_at: now,
      privacy_policy_accepted_at: now,
      terms_version: CURRENT_TERMS_VERSION,
      privacy_policy_version: CURRENT_PRIVACY_POLICY_VERSION,
      consent_source: consent[:source],
      marketing_consent: explicit_true?(consent[:marketing_consent])
    }
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

  # Always returns a persisted preferences row (creates the default, opt-out row
  # on first access). Use this instead of the raw association when reading/writing
  # notification settings.
  def notification_preferences!
    notification_preferences || create_notification_preferences!
  end

  private

  def email_not_blocked
    errors.add(:email, "não pode mais ser usado para criar uma conta") if BlockedEmail.blocked?(email)
  end

  def normalize_signup_source
    self.signup_source = "unknown" unless SIGNUP_SOURCES.include?(signup_source)
  end

  def start_app_trial
    return if trial_started_at.present?
    update_columns(
      trial_started_at: created_at,
      trial_ends_at: created_at + TRIAL_DURATION_DAYS.days
    )
    UserEventService.track(
      user: self,
      event: :user_created,
      occurred_at: created_at,
      idempotency_key: "user_created:#{id}"
    )
    UserEventService.track(
      user: self,
      event: :trial_started,
      occurred_at: trial_started_at,
      metadata: { trial_ends_at: trial_ends_at },
      idempotency_key: "trial_started:#{id}:#{trial_started_at.to_date}"
    )
    UserEventService.track(
      user: self,
      event: :signup_completed,
      occurred_at: created_at,
      idempotency_key: "signup_completed:#{id}"
    )
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

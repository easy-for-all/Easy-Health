class AccountDeletionService
  def initialize(user)
    @user = user
  end

  def call
    ActiveRecord::Base.transaction do
      timestamp = Time.current
      user_id = @user.id
      original_email = @user.email

      # Destroy personal data (cascades via dependent: :destroy)
      @user.health_profile&.destroy!
      @user.fitness_profile&.destroy!
      @user.workout_plans.destroy_all
      @user.workout_sessions.destroy_all
      @user.user_media.each { |m| m.file.purge_later; m.destroy! }
      @user.health_data_points.destroy_all
      @user.ai_usage_logs.destroy_all
      @user.avatar.purge_later if @user.avatar.attached?

      # Anonymize subscription (keep stripe_subscription_id for legal/compliance
      # reference, clear stripe_customer_id instead of writing a fake id so it
      # never gets reused as a real Stripe customer on a future checkout)
      @user.subscription&.update_columns(stripe_customer_id: nil)

      # Anonymize user record
      @user.update_columns(
        name: "Deleted User",
        email: "deleted_#{user_id}@easyhealth.invalid",
        encrypted_password: SecureRandom.hex(32),
        deletion_requested_at: timestamp,
        anonymized_at: timestamp
      )

      # Block the original email (and any Google identity tied to this row)
      # from ever being used to sign up again.
      BlockedEmail.block!(email: original_email, user_id: user_id)
    end
  end
end

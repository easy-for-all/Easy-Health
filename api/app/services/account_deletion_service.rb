class AccountDeletionService
  def initialize(user)
    @user = user
  end

  def call
    ActiveRecord::Base.transaction do
      timestamp = Time.current
      user_id = @user.id

      # Destroy personal data (cascades via dependent: :destroy)
      @user.health_profile&.destroy!
      @user.fitness_profile&.destroy!
      @user.workout_plans.destroy_all
      @user.workout_sessions.destroy_all
      @user.user_media.each { |m| m.file.purge_later; m.destroy! }
      @user.health_data_points.destroy_all
      @user.ai_usage_logs.destroy_all
      @user.avatar.purge_later if @user.avatar.attached?

      # Anonymize subscription (keep for legal/compliance, remove personal references)
      if @user.subscription.present?
        @user.subscription.update_columns(stripe_customer_id: "deleted_#{user_id}")
      end

      # Anonymize user record
      @user.update_columns(
        name: "Deleted User",
        email: "deleted_#{user_id}@easyhealth.invalid",
        encrypted_password: SecureRandom.hex(32),
        deletion_requested_at: timestamp,
        anonymized_at: timestamp
      )
    end
  end
end

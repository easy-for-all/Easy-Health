module Analytics
  # Persistence-only base for future product experiments (push vs control, CTA,
  # onboarding, etc.). Namespaced to avoid colliding with the pre-existing
  # top-level ExperimentAssignment service (activation-push A/B).
  class ExperimentAssignment < ApplicationRecord
    self.table_name = "analytics_experiment_assignments"

    belongs_to :user, optional: true

    validates :experiment_key, :variant, :assigned_at, presence: true
    validate :user_or_anonymous_present

    scope :for_experiment, ->(key) { where(experiment_key: key) }

    private

    def user_or_anonymous_present
      return if user_id.present? || anonymous_id.present?

      errors.add(:base, "requires user_id or anonymous_id")
    end
  end
end

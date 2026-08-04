module Analytics
  # Persistence-only base for future product experiments (push vs control, CTA,
  # onboarding, etc.). Namespaced to avoid colliding with the pre-existing
  # top-level ExperimentAssignment service (activation-push A/B).
  class ExperimentAssignment < ApplicationRecord
    self.table_name = "analytics_experiment_assignments"

    belongs_to :user, optional: true

    validates :experiment_key, :variant, :assigned_at, presence: true
    validate :subject_present

    scope :for_experiment, ->(key) { where(experiment_key: key) }
    scope :for_installation, ->(id) { where(installation_id: id) }

    private

    # Three identity spaces, one row each: a logged-in user, an analytics
    # anonymous_id, or an installation. installation_id is the one pre-auth
    # Android experiments use — see the migration for why it is not folded into
    # anonymous_id.
    def subject_present
      return if user_id.present? || anonymous_id.present? || installation_id.present?

      errors.add(:base, "requires user_id, anonymous_id or installation_id")
    end
  end
end

class AiTrainingDecisionLog < ApplicationRecord
  # Segue o dono do plano que o originou. Como AiUsageLog, não troca de dono no
  # claim — mas o `ai_rationale` que a tela de plano pronto mostra continua
  # acessível, porque a associação é por workout_plan_id, não por usuário.
  belongs_to :user, optional: true
  belongs_to :app_installation, optional: true
  belongs_to :workout_plan
  belongs_to :ai_prompt_version, optional: true

  STATUSES = %w[success fallback_used validation_failed error].freeze

  validates :status, inclusion: { in: STATUSES }, allow_nil: true
  validate :owner_present

  scope :recent,     -> { order(created_at: :desc) }
  scope :successful, -> { where(status: "success") }
  scope :today,      -> { where(created_at: Time.current.all_day) }
  scope :anonymous,  -> { where(user_id: nil) }

  private

  def owner_present
    return if user_id.present? || app_installation_id.present?

    errors.add(:base, "requires user or app_installation")
  end
end

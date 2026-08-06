class WorkoutPlan < ApplicationRecord
  # Um plano tem exatamente um dono: um usuário OU uma instalação (Android
  # nativo, antes de a conta existir). O banco garante isso com o CHECK
  # workout_plans_single_owner; a validação aqui existe para que a violação
  # apareça como erro de modelo em vez de exceção crua do Postgres.
  belongs_to :user, optional: true
  belongs_to :app_installation, optional: true

  has_many :workout_days, dependent: :destroy
  has_one :ai_training_decision_log, dependent: :destroy
  has_one :workout_strategy, dependent: :destroy

  validate :exactly_one_owner

  scope :active, -> { where(active: true) }
  scope :owned_by_installation, ->(installation) { where(app_installation_id: installation) }
  scope :anonymous, -> { where(user_id: nil) }

  def anonymous?
    user_id.nil?
  end

  private

  def exactly_one_owner
    return if user_id.present? ^ app_installation_id.present?

    errors.add(:base, "requires exactly one owner (user or app_installation)")
  end
end

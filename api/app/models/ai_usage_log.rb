class AiUsageLog < ApplicationRecord
  # A geração anônima também custa dinheiro, então também é contabilizada — só
  # que atribuída à instalação. Estas linhas NÃO trocam de dono no claim: o
  # RateLimiter conta este modelo por usuário e por dia, e reatribuir faria a
  # pessoa chegar à conta nova já no teto.
  belongs_to :user, optional: true
  belongs_to :app_installation, optional: true

  validate :owner_present

  scope :today,     -> { where(created_at: Date.current.all_day) }
  scope :for_task,  ->(t) { where(task_type: t.to_s) }
  scope :anonymous, -> { where(user_id: nil) }

  private

  def owner_present
    return if user_id.present? || app_installation_id.present?

    errors.add(:base, "requires user or app_installation")
  end
end

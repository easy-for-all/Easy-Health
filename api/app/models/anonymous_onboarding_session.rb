# O estado de quem está usando o app sem conta, e a autoridade sobre quantos
# planos essa instalação ainda pode gerar.
#
# O contador vive AQUI e não num COUNT em workout_plans de propósito: uma
# geração que falha depois de chamar o provedor já custou dinheiro e não deixou
# plano nenhum. Contar planos existentes transformaria cada erro num crédito, e
# um loop de retry em geração ilimitada.
class AnonymousOnboardingSession < ApplicationRecord
  # Teto de vida da instalação. O 4º pedido exige conta — é onde o valor
  # entregue de graça termina e o cadastro passa a ser o preço.
  MAX_PLANS = 3

  # Teto por dia, independente do teto de vida. Existe para o caso em que o de
  # vida ainda não foi atingido mas alguém está queimando geração em sequência.
  DEFAULT_DAILY_MAX = 3

  GENERATION_STATUSES = %w[success failed limit_reached unavailable].freeze

  # Vocabulário fechado, igual ao de AppInstallations::LinkToUser. Um código
  # fora desta lista significa que alguém inventou um estado que o painel não
  # sabe ler.
  CLAIM_FAILURE_CODES = %w[user_conflict installation_conflict claim_error].freeze

  belongs_to :app_installation
  belongs_to :claimed_by_user, class_name: "User", optional: true

  validates :app_installation_id, uniqueness: true
  validates :plans_generated_count, :plans_generated_today_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :last_generation_status, inclusion: { in: GENERATION_STATUSES }, allow_blank: true
  validates :last_claim_failure_code, inclusion: { in: CLAIM_FAILURE_CODES }, allow_blank: true

  scope :claimed,   -> { where.not(claimed_at: nil) }
  scope :unclaimed, -> { where(claimed_at: nil) }
  scope :at_limit,  -> { where("plans_generated_count >= ?", MAX_PLANS) }

  def self.daily_max
    raw = ENV["ANONYMOUS_GENERATION_DAILY_MAX"].to_s.strip
    raw.match?(/\A\d+\z/) ? Integer(raw) : DEFAULT_DAILY_MAX
  end

  def claimed?
    claimed_at.present?
  end

  def plans_remaining
    [ MAX_PLANS - plans_generated_count, 0 ].max
  end

  def at_limit?
    plans_remaining.zero?
  end

  # Zera a janela diária quando o dia virou. Cortado no fuso de REPORTING e não
  # em UTC: para quem gera às 22h de Brasília, o dia UTC já é o seguinte, e o
  # limite "por dia" pareceria reiniciar no meio da noite.
  def roll_daily_counter!
    today = Analytics::ReportingTime.today
    return if counter_date == today

    self.counter_date = today
    self.plans_generated_today_count = 0
  end

  def daily_limit_reached?
    plans_generated_today_count >= self.class.daily_max
  end
end

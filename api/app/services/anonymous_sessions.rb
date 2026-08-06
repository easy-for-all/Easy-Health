# Configuração do modo anônimo, lida em tempo de chamada.
#
# Nada aqui é congelado em constante no boot: o kill-switch precisa desligar a
# geração anônima num servidor em produção sem deploy — é o único controle que
# realmente limita a conta de OpenAI se algo der errado.
module AnonymousSessions
  DEFAULT_MIN_BUILD = 0

  # Teto global diário de gerações anônimas. Existe porque os limites por
  # instalação são por instalação: 10 mil instalações no limite ainda somam
  # 30 mil gerações, e nenhum contador local percebe isso.
  DEFAULT_DAILY_GLOBAL_MAX = 500

  module_function

  # Default LIGADO seria a escolha errada aqui. Este flag não protege dados, ele
  # protege dinheiro: um endpoint sem autenticação que chama a OpenAI só deve
  # existir onde alguém decidiu explicitamente que deve.
  def enabled?
    ENV["ANONYMOUS_GENERATION_ENABLED"].to_s.strip == "true"
  end

  def min_build
    raw = ENV["ANONYMOUS_MODE_MIN_BUILD"].to_s.strip
    raw.match?(/\A\d+\z/) ? Integer(raw) : DEFAULT_MIN_BUILD
  end

  # Um build que o servidor não consegue ler não entra. Errar para "fora" custa
  # um usuário que cria conta pelo fluxo antigo; errar para "dentro" abre a
  # geração para qualquer cliente que omita o header.
  def build_eligible?(build_number)
    minimum = min_build
    return true if minimum.zero?

    raw = build_number.to_s.strip
    raw.match?(/\A\d+\z/) && Integer(raw) >= minimum
  end

  def daily_global_max
    raw = ENV["ANONYMOUS_GENERATION_DAILY_GLOBAL_MAX"].to_s.strip
    raw.match?(/\A\d+\z/) ? Integer(raw) : DEFAULT_DAILY_GLOBAL_MAX
  end
end

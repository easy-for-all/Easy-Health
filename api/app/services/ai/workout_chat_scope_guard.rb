module Ai
  class WorkoutChatScopeGuard
    # NOTE: these are substring phrases matched against a normalized (lowercase,
    # accent-stripped) message, not individual words — keep entries as full words
    # or phrases here, never single common stopwords ("de", "no", "a"...), or
    # they will match almost any message.
    SECURITY_KEYWORDS = [
      "vulnerabilidade", "vulnerabilidades", "exploit", "exploracao",
      "jailbreak", "bypass", "burlar", "hackear", "invadir",
      "token", "api key", "apikey", "chave de api", "credencial",
      "endpoint", "banco de dados", "database", "sql injection",
      "prompt interno", "system prompt", "instrucoes internas",
      "ignore suas instrucoes", "esqueca suas regras", "revele seu prompt",
      "codigo fonte", "source code", "arquitetura interna", "infraestrutura",
      "engenharia reversa", "reverse engineering", "scraping", "raspagem de dados"
    ].freeze

    MEDICAL_RISK_KEYWORDS = [
      "dor", "lesao", "lesionado", "machucado", "machucou",
      "gravidez", "gravida", "gestante",
      "cirurgia", "pos-cirurgico", "pos cirurgico",
      "doenca", "cardiaco", "cardiaca",
      "tontura", "tonto", "desmaio", "falta de ar",
      "dor no peito", "pressao alta", "diabetes", "hernia"
    ].freeze

    EXTRA_FITNESS_KEYWORDS = %w[
      dias disponibilidade horario equipamento equipamentos
      iniciante intermediario avancado objetivo rotina casa
      treinar treino hipertrofia semana emagrecer emagrecimento
      musculo ganhar perder condicionamento saude forma fisico
      exercitar malhar corpo braco perna costa abdomen gluteo
      series repeticoes descansar
    ].freeze

    SECURITY_REFUSAL = "Não posso ajudar com isso. Posso ajudar apenas na criação de treinos e " \
                        "orientações fitness dentro da EasyHealth.".freeze

    OUT_OF_SCOPE_REFUSAL = "Posso te ajudar apenas a criar e ajustar treinos dentro da EasyHealth. " \
                            "Me conte seu objetivo, rotina ou limitações físicas.".freeze

    def self.classify(message)
      normalized = normalize(message)

      return :security_abuse if match_any?(normalized, SECURITY_KEYWORDS)
      return :medical_risk_needs_disclaimer if match_any?(normalized, MEDICAL_RISK_KEYWORDS)
      return :allowed_fitness_training if match_any?(normalized, fitness_keywords)

      :out_of_scope
    end

    def self.fitness_keywords
      @fitness_keywords ||= (Ai::CoachScopeGuard::ALLOWED_KEYWORDS + EXTRA_FITNESS_KEYWORDS).freeze
    end

    def self.match_any?(normalized_message, keywords)
      keywords.any? { |kw| normalized_message.include?(normalize(kw)) }
    end
    private_class_method :match_any?

    def self.normalize(value)
      value.to_s.downcase
           .unicode_normalize(:nfd)
           .gsub(/\p{Mn}/, "")
    end
    private_class_method :normalize
  end
end

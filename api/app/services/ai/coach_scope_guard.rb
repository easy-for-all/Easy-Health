module Ai
  class CoachScopeGuard
    ALLOWED_KEYWORDS = %w[
      treino exercicio exercício musculacao musculação cardio
      carga repetição repeticao reps série series peso gordura
      massa evolução evolucao frequencia frequência volume
      corrida caminhada bike esteira eliptico hiit funcional
      alimentação alimentacao dieta caloria proteína proteina
      carboidrato gordura descanso sono recuperação recuperacao
      dor lesão lesao alongamento aquecimento
      supino agachamento terra deadlift rosca remada
      easyhealth plano assinatura app sessão sessao
      força forca resistencia resistência flexao flexão
      aerobico aeróbico anaerobico anaeróbico
      bcaa creatina suplemento hidratação hidratacao
      academia ginasio ginásio personal trainer
    ].freeze

    BLOCKED_RESPONSE = "Posso te ajudar apenas com treino, evolução física, saúde fitness, " \
                       "alimentação, uso do EasyHealth e seu plano dentro do app. " \
                       "Me manda algo nessa linha que eu te ajudo 💪"

    def self.allowed?(message)
      normalized = message.to_s.downcase
                          .unicode_normalize(:nfd)
                          .gsub(/\p{Mn}/, "")
      ALLOWED_KEYWORDS.any? { |kw| normalized.include?(kw) }
    end
  end
end

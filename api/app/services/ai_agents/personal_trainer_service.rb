module AiAgents
  class PersonalTrainerService < BaseAgentService
    def call
      progression = exercise_progression
      return { recommendations: [], message: "Treine mais alguns dias para receber recomendações personalizadas." } if progression.empty?

      prompt = build_prompt(progression)
      raw = call_claude(prompt, :agent_personal_trainer)
      return { recommendations: [], message: "Não foi possível gerar análise agora. Tente novamente mais tarde." } if raw.blank?

      recommendations = parse_recommendations(raw)
      { recommendations: recommendations, analyzed_sessions: recent_sessions.size }
    end

    private

    def build_prompt(progression)
      progression_text = progression.map do |name, entries|
        recent = entries.first(3)
        weights = recent.map { |e| e[:avg_weight] }.reject(&:zero?)
        trend = if weights.size >= 2
          diff = weights.first - weights.last
          diff > 1 ? "aumentando" : diff < -1 ? "reduzindo" : "estável"
        else
          "insuficiente"
        end
        completion_rate = recent.any? ? (recent.sum { |e| e[:sets_done].to_f / [e[:sets_plan], 1].max } / recent.size * 100).round : 0
        "#{name}: peso médio #{weights.first || 0}kg, tendência #{trend}, conclusão #{completion_rate}%"
      end.join("\n")

      <<~PROMPT
        Você é um personal trainer experiente analisando o progresso de um atleta.
        Responda APENAS em JSON válido, sem texto adicional, no formato abaixo.
        Use português brasileiro. Seja específico, prático e motivador.

        Histórico de exercícios (mais recente primeiro):
        #{progression_text}

        Gere entre 2 e 4 recomendações no formato JSON:
        [
          {
            "exercise": "Nome do Exercício",
            "action": "aumentar_peso|reduzir_peso|manter|alterar_reps|alterar_series|deload|progressao",
            "suggestion": "Texto curto explicando o que fazer (ex: Aumente para 62kg)",
            "reason": "Por que essa recomendação (1 frase)",
            "priority": "high|medium|low"
          }
        ]

        Somente retorne o array JSON, sem introdução ou explicação.
      PROMPT
    end

    def parse_recommendations(raw)
      json_str = raw.match(/\[.*\]/m)&.to_s
      return [] if json_str.blank?

      parsed = JSON.parse(json_str)
      parsed.map do |r|
        {
          exercise:   r["exercise"],
          action:     r["action"],
          suggestion: r["suggestion"],
          reason:     r["reason"],
          priority:   r["priority"] || "medium"
        }
      end
    rescue JSON::ParserError => e
      Rails.logger.error("[PersonalTrainerService] JSON parse error: #{e.message}")
      []
    end
  end
end

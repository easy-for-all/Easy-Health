module AiAgents
  class ConditioningService < BaseAgentService
    def call
      sessions = recent_sessions.to_a
      return { recommendations: [], message: "Treine mais alguns dias para receber análise de condicionamento." } if sessions.size < 2

      prompt = build_prompt(sessions)
      raw = call_claude(prompt, :agent_conditioning)
      return { recommendations: [], message: "Não foi possível gerar análise agora." } if raw.blank?

      recommendations = parse_recommendations(raw)
      {
        recommendations: recommendations,
        stats: compute_stats(sessions)
      }
    end

    private

    def compute_stats(sessions)
      durations = sessions.map(&:duration_minutes)
      weekly_freq = sessions.group_by { |s| s.completed_at.beginning_of_week }.map { |_, v| v.size }
      avg_rest = sessions.flat_map { |s|
        (s.exercise_logs || []).map { |l| l["rest_seconds"].to_i }
      }.reject(&:zero?).then { |arr| arr.any? ? arr.sum / arr.size : 0 }

      {
        avg_duration:    (durations.sum.to_f / durations.size).round,
        sessions_count:  sessions.size,
        avg_weekly_freq: weekly_freq.any? ? (weekly_freq.sum.to_f / weekly_freq.size).round(1) : 0,
        avg_rest_seconds: avg_rest
      }
    end

    def build_prompt(sessions)
      stats = compute_stats(sessions)
      recent_dates = sessions.first(5).map { |s| s.completed_at.strftime("%d/%m") }.join(", ")

      <<~PROMPT
        Você é um especialista em condicionamento físico analisando a evolução de um atleta.
        Responda APENAS em JSON válido, sem texto adicional.
        Use português brasileiro. Seja encorajador e prático.

        Dados do atleta:
        - Sessões analisadas: #{stats[:sessions_count]}
        - Duração média: #{stats[:avg_duration]} minutos
        - Frequência média: #{stats[:avg_weekly_freq]} treinos/semana
        - Descanso médio entre séries: #{stats[:avg_rest_seconds]}s
        - Datas recentes: #{recent_dates}

        Gere entre 2 e 3 recomendações de condicionamento no formato JSON:
        [
          {
            "category": "frequencia|duracao|descanso|cardio|circuito|intensidade",
            "suggestion": "Texto curto e prático do que fazer",
            "reason": "Por que isso vai melhorar o condicionamento (1 frase)",
            "priority": "high|medium|low"
          }
        ]

        Somente retorne o array JSON.
      PROMPT
    end

    def parse_recommendations(raw)
      json_str = raw.match(/\[.*\]/m)&.to_s
      return [] if json_str.blank?

      parsed = JSON.parse(json_str)
      parsed.map do |r|
        {
          category:   r["category"],
          suggestion: r["suggestion"],
          reason:     r["reason"],
          priority:   r["priority"] || "medium"
        }
      end
    rescue JSON::ParserError => e
      Rails.logger.error("[ConditioningService] JSON parse error: #{e.message}")
      []
    end
  end
end

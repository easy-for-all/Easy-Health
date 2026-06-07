module AiAgents
  class CoachService < BaseAgentService
    HISTORY_TURNS = 6

    def initialize(user, messages:, context: {}, training_context: nil)
      super(user)
      @messages         = Array(messages).last(HISTORY_TURNS)
      @context          = context.to_h.with_indifferent_access
      @training_context = training_context
    end

    def call
      prompt = build_prompt
      call_claude(prompt, :coach_chat)
    end

    private

    def build_prompt
      [persona, profile_summary, training_context_block, context_block, history_block, instruction].join("\n\n")
    end

    def persona
      <<~TEXT.strip
        Você é o Coach EasyHealth, personal trainer de IA integrado ao app de treino.
        Tom técnico e objetivo, focado em dados e progressão real.
        Português do Brasil. Máximo 3 frases curtas e práticas.
        Cite carga, reps ou séries quando ajudar. Máximo 1 emoji por resposta.
        Sem títulos, listas longas ou markdown excessivo.
        Não invente lesões nem diagnósticos médicos.
        Use **negrito** apenas para destacar o essencial.
        NUNCA diga que precisa de dados que já estão no contexto abaixo.
        NUNCA invente dados — se algo não estiver no contexto, diga exatamente o que falta.
      TEXT
    end

    def profile_summary
      hp = @user.health_profile
      return "Perfil do aluno: não cadastrado ainda." unless hp

      parts = [
        "Objetivo: #{hp.goal}",
        "Nível: #{hp.fitness_level}",
        "#{hp.training_days_per_week || '?'} dias/semana",
        "Local: #{hp.training_location || 'não informado'}"
      ]
      parts << "Modalidade: #{hp.modality}" if hp.modality
      "Perfil do aluno: #{parts.join(' | ')}"
    end

    def training_context_block
      return "" unless @training_context

      tc = @training_context
      lines = ["=== CONTEXTO REAL DO USUÁRIO ==="]
      lines << "Data/hora: #{tc[:current_datetime]} (#{tc[:current_weekday]})"

      if (plan = tc[:active_plan])
        lines << "Plano ativo: #{plan[:days_count]} dias de treino configurados"
      else
        lines << "Plano ativo: nenhum plano configurado"
      end

      if (today = tc[:today_workout])
        exercises_text = (today[:exercises] || []).map do |e|
          "#{e[:name]} (#{e[:muscle_group]}) — #{e[:sets]}x#{e[:reps]}, #{e[:rest_seconds]}s descanso"
        end.join("; ")
        lines << "Treino de hoje (#{today[:name]}): #{exercises_text.presence || 'sem exercícios configurados'}"
      else
        lines << "Treino de hoje: nenhum treino configurado para hoje"
      end

      if (last = tc[:last_session])
        date = last[:completed_at]&.strftime("%d/%m/%Y às %H:%M") || "data desconhecida"
        ex_text = (last[:exercises] || []).map do |e|
          weights = Array(e[:weight_kg]).map { |w| "#{w}kg" }.join("/")
          reps    = Array(e[:reps]).join("/")
          "#{e[:name]}: #{weights} × #{reps} reps (#{e[:sets]} séries)"
        end.join("; ")
        lines << "Última sessão (#{date}, #{last[:duration_minutes]}min, fadiga #{last[:fatigue_level]}/5): #{ex_text}"
      else
        lines << "Última sessão: nenhuma sessão registrada ainda"
      end

      if (evo = tc[:evolution])
        lines << "Evolução: #{evo[:last_7_days]} treinos nos últimos 7 dias, " \
                 "#{evo[:last_30_days]} nos últimos 30 dias, " \
                 "volume total no mês: #{evo[:total_volume_30d]} kg"
      end

      lines << "=== FIM DO CONTEXTO ==="
      lines.join("\n")
    end

    def context_block
      lines = ["Tela atual: #{@context[:screen] || 'dashboard'}"]
      if @context[:exercise_name].present?
        lines << "Exercício em foco: #{@context[:exercise_name]}" \
                 "#{" (#{@context[:muscle_group]})" if @context[:muscle_group].present?}" \
                 "#{" — #{@context[:set_info]}" if @context[:set_info].present?}"
      end
      lines.join("\n")
    end

    def history_block
      return "" if @messages.empty?

      turns = @messages.map do |m|
        label = m[:role] == "user" ? "Aluno" : "Coach"
        "#{label}: #{m[:content]}"
      end
      "Conversa recente:\n#{turns.join("\n")}"
    end

    def instruction
      "Responda à última mensagem do aluno usando obrigatoriamente os dados do contexto acima. Seja direto."
    end
  end
end

module AiAgents
  class CoachService < BaseAgentService
    HISTORY_TURNS = 6

    def initialize(user, messages:, context: {})
      super(user)
      @messages = Array(messages).last(HISTORY_TURNS)
      @context  = context.to_h.with_indifferent_access
    end

    def call
      prompt = build_prompt
      call_claude(prompt, :coach_chat)
    end

    private

    def build_prompt
      [persona, profile_summary, context_block, history_block, instruction].join("\n\n")
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
      TEXT
    end

    def profile_summary
      hp = @user.health_profile
      return "Perfil do aluno: não cadastrado ainda." unless hp

      parts = [
        "Objetivo: #{hp.goal}",
        "Nível: #{hp.fitness_level}",
        "#{hp.training_days_per_week || '?'} dias/semana",
        "Local: #{hp.training_location || 'não informado'}",
      ]
      parts << "Modalidade: #{hp.modality}" if hp.modality
      "Perfil do aluno: #{parts.join(' | ')}"
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
      "Responda à última mensagem do aluno de forma direta."
    end
  end
end

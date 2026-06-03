module AiAgents
  class WorkoutPlannerService < BaseAgentService
    VALID_METHODS  = %w[full_body upper_lower ab abc ppl custom].freeze
    VALID_GROUPS   = %w[chest back shoulders biceps triceps legs core forearms calves glutes trapezius].freeze
    MAX_SESSIONS   = 10
    MAX_EXERCISES_IN_PROMPT = 5

    def initialize(user, days_per_week:, profile:, fav_exercise_ids: [], available_exercises: {})
      super(user)
      @days_per_week       = days_per_week
      @profile             = profile
      @fav_exercise_ids    = fav_exercise_ids
      @available_exercises = available_exercises
    end

    def call
      prompt = build_prompt
      raw    = call_claude(prompt, :workout_planning)
      return nil if raw.blank?

      parse_response(raw)
    rescue => e
      Rails.logger.error("[WorkoutPlannerService] error: #{e.message}")
      nil
    end

    private

    def build_prompt
      <<~PROMPT
        Você é um especialista em prescrição de treino personalizado.
        Analise o perfil abaixo e retorne SOMENTE um JSON válido, sem texto adicional.

        ## PERFIL DO USUÁRIO
        - Nível: #{@profile&.fitness_level || "beginner"}
        - Objetivo: #{@profile&.goal || "saude"}
        - Modalidade: #{@profile&.modality || "musculacao"}
        - Local de treino: #{@profile&.training_location || "gym"}
        - Dias disponíveis por semana: #{@days_per_week}
        - Sexo: #{@profile&.gender || "não informado"}
        - Idade: #{@profile&.age || "não informada"}
        - Peso: #{@profile&.weight_kg ? "#{@profile.weight_kg} kg" : "não informado"}
        - Altura: #{@profile&.height_cm ? "#{@profile.height_cm} cm" : "não informada"}
        - Limitações físicas: #{Array(@profile&.limitations).join(", ").presence || "nenhuma"}
        - Estilos preferidos: #{Array(@profile&.preferred_training_styles).join(", ").presence || "não informado"}

        ## HISTÓRICO DE TREINOS (últimas #{MAX_SESSIONS} sessões)
        #{sessions_context}

        ## PROGRESSÃO DE CARGA (top exercícios)
        #{progression_context}

        ## EXERCÍCIOS FAVORITOS
        #{favorites_context}

        ## DIAS/TREINOS FAVORITOS
        #{favorite_days_context}

        ## EXERCÍCIOS DISPONÍVEIS NO SISTEMA (por grupo muscular)
        #{available_exercises_context}

        ## INSTRUÇÕES
        Escolha o método de treino mais adequado para este perfil e retorne o JSON abaixo.
        Métodos válidos: #{VALID_METHODS.join(", ")}.
        Grupos musculares válidos: #{VALID_GROUPS.join(", ")}.
        Número de dias no week_structure: exatamente #{@days_per_week}.
        Cada dia deve ter entre 2 e 5 muscle_groups.
        Séries e repetições devem ser adequadas ao nível do usuário.
        Não exagere volume para iniciantes (máx 3 exercícios por grupo muscular).
        Segurança: nunca coloque o mesmo grupo muscular em dias consecutivos sem recuperação.
        Se o objetivo for emagrecimento ou condicionamento, inclua sugestão de cardio nas safety_notes.

        ## FORMATO DE RESPOSTA (JSON puro, sem markdown)
        {
          "training_method": "upper_lower",
          "plan_name": "Plano Hipertrofia — Superior/Inferior",
          "rationale": "Explicação em português de por que este método foi escolhido para este perfil específico (2-3 frases)",
          "week_structure": [
            { "name": "Superior A", "muscle_groups": ["chest", "back", "shoulders"] },
            { "name": "Inferior",   "muscle_groups": ["legs", "core"] }
          ],
          "sets": 3,
          "reps": 10,
          "rest_seconds": 90,
          "progression_strategy": "Semana 1: adaptação com foco em técnica. Semana 2: aumentar 1 repetição por série. Semana 3: aumentar carga em 5-10%. Semana 4: deload leve.",
          "safety_notes": ["Aquecer 5-10 min antes de cada treino", "Descansar 48h antes de treinar o mesmo grupo muscular"]
        }
      PROMPT
    end

    def sessions_context
      sessions = @user.workout_sessions.order(completed_at: :desc).limit(MAX_SESSIONS)
      return "Nenhuma sessão registrada ainda." if sessions.empty?

      lines = sessions.map do |s|
        date = s.completed_at.strftime("%d/%m/%Y")
        duration = s.duration_minutes ? "#{s.duration_minutes} min" : "duração desconhecida"
        fatigue  = s.fatigue_level ? "fadiga #{s.fatigue_level}/5" : nil
        exercises_done = (s.exercise_logs || []).size
        [date, duration, "#{exercises_done} exercícios", fatigue].compact.join(" | ")
      end
      lines.join("\n")
    end

    def progression_context
      prog = exercise_progression
      return "Sem dados de progressão ainda." if prog.empty?

      prog.first(MAX_EXERCISES_IN_PROMPT).map do |name, entries|
        recent  = entries.first(3)
        weights = recent.map { |e| e[:avg_weight] }.reject(&:zero?)
        trend   = if weights.size >= 2
          diff = weights.first - weights.last
          diff > 1 ? "carga crescendo" : diff < -1 ? "carga reduzindo" : "carga estável"
        else
          "dados insuficientes"
        end
        "#{name}: #{trend} (último #{weights.first || 0}kg)"
      end.join("\n")
    end

    def favorites_context
      return "Nenhum exercício favorito." if @fav_exercise_ids.empty?

      exercises = Exercise.where(id: @fav_exercise_ids).limit(10)
      return "Nenhum exercício favorito." if exercises.empty?

      exercises.map { |ex| "#{ex.name} (#{ex.muscle_group})" }.join(", ")
    end

    def favorite_days_context
      plan = @user.active_workout_plan
      return "Nenhum." unless plan

      fav_days = plan.workout_days.where(favorited: true).pluck(:name)
      fav_days.any? ? fav_days.join(", ") : "Nenhum."
    end

    def available_exercises_context
      @available_exercises.map do |group, count|
        "#{group}: #{count} exercícios disponíveis"
      end.join(", ")
    end

    def parse_response(raw)
      json_str = raw.match(/\{.*\}/m)&.to_s
      return nil if json_str.blank?

      data = JSON.parse(json_str)

      method       = data["training_method"].to_s
      week_struct  = Array(data["week_structure"])
      sets         = data["sets"].to_i.clamp(1, 6)
      reps         = data["reps"].to_i.clamp(1, 30)
      rest         = data["rest_seconds"].to_i.clamp(0, 300)

      return nil unless VALID_METHODS.include?(method)
      return nil if week_struct.empty?

      normalized_structure = week_struct.first(@days_per_week).map do |day|
        groups = Array(day["muscle_groups"]).select { |g| VALID_GROUPS.include?(g.to_s) }
        next nil if groups.empty?
        { name: day["name"].to_s.presence || "Treino", muscle_groups: groups }
      end.compact

      return nil if normalized_structure.empty?

      {
        training_method:     method,
        plan_name:           data["plan_name"].to_s.presence || "Plano Personalizado",
        rationale:           data["rationale"].to_s,
        week_structure:      normalized_structure,
        sets_reps:           { sets: sets, reps: reps, rest_seconds: rest },
        progression_strategy: data["progression_strategy"].to_s,
        safety_notes:        Array(data["safety_notes"]).map(&:to_s)
      }
    rescue JSON::ParserError => e
      Rails.logger.error("[WorkoutPlannerService] JSON parse error: #{e.message}")
      nil
    end
  end
end

module Api
  module V1
    class QuickWorkoutsController < BaseController
      include ExerciseImageHelper

      DIFFICULTY_PARAMS = {
        "iniciante" => { sets: 3, reps: 10, rest_seconds: 90 },
        "moderado"  => { sets: 4, reps: 10, rest_seconds: 75 },
        "intenso"   => { sets: 4, reps: 12, rest_seconds: 60 }
      }.freeze

      OUTDOOR_EQUIPMENT = %w[bodyweight cardio].freeze
      ALL_MUSCLE_GROUPS  = %w[chest back legs shoulders biceps triceps core].freeze

      # Modalities that select exercises from the DB
      EXERCISE_BASED_MODALITIES = %w[musculacao funcional mobilidade alongamento].freeze

      # Modalities that map to a specific DB exercise_type
      MODALITY_TO_EXERCISE_TYPE = {
        "musculacao"  => "musculacao",
        "funcional"   => "funcional",
        "mobilidade"  => "timed",
        "alongamento" => "timed",
      }.freeze

      # Modalities that generate structured session blocks (no DB exercises)
      SESSION_BASED_MODALITIES = %w[corrida bike caminhada hiit cardio].freeze

      CARDIO_MODALITIES = %w[corrida bike cardio caminhada].freeze
      STRENGTH_MODALITIES = %w[musculacao funcional mobilidade alongamento].freeze

      def create
        duration   = params[:duration_minutes].to_i.clamp(10, 90)
        difficulty = params[:difficulty].presence || "moderado"
        location   = params[:location].presence || "academia"
        modality   = params[:modality].presence || "ai_choice"

        raw_groups     = Array(params[:muscle_groups]).map(&:presence).compact
        muscle_groups  = raw_groups.any? ? raw_groups : ALL_MUSCLE_GROUPS

        params_sr      = DIFFICULTY_PARAMS[difficulty] || DIFFICULTY_PARAMS["moderado"]

        fav_ids = current_user.user_favorite_exercises.pluck(:exercise_id)

        if SESSION_BASED_MODALITIES.include?(modality)
          blocks = build_session_blocks(modality, difficulty, duration)
          render json: {
            day: {
              id: nil,
              name: workout_name(modality, muscle_groups, difficulty),
              quick: true,
              exercises: blocks
            }
          }, status: :created
        else
          exercise_count = (duration / 8.0).round.clamp(3, 12)
          chosen_exercises = build_exercises(modality, muscle_groups, location, exercise_count, fav_ids)

          render json: {
            day: {
              id: nil,
              name: workout_name(modality, muscle_groups, difficulty),
              quick: true,
              exercises: chosen_exercises.each_with_index.map do |ex, idx|
                timed = ex.exercise_type == "timed"
                cardio = WorkoutDayExercise::CARDIO_TYPES.include?(ex.exercise_type)
                {
                  workout_day_exercise_id: -(idx + 1),
                  exercise_id: ex.id,
                  name: ex.name,
                  muscle_group: ex.muscle_group,
                  exercise_type: ex.exercise_type,
                  description: ex.description,
                  instructions: ex.instructions,
                  image_url: exercise_image_url(ex),
                  gif_url: ex.gif_url,
                  video_url: ex.video_url,
                  muscle_image_url: muscle_image_url(ex.muscle_group),
                  sets: timed || cardio ? nil : params_sr[:sets],
                  reps: timed || cardio ? nil : params_sr[:reps],
                  rest_seconds: timed ? nil : params_sr[:rest_seconds],
                  duration_minutes: (timed || cardio) ? (ex.duration_minutes || 60) : nil,
                  intensity: cardio ? "moderado" : nil,
                  order_index: idx,
                  is_favorite: fav_ids.include?(ex.id),
                  last_performed_at: nil
                }
              end
            }
          }, status: :created
        end
      end

      private

      # ── Session-based workouts (bike, corrida, caminhada, hiit) ────────────

      def build_session_blocks(modality, difficulty, duration)
        case modality
        when "bike"     then bike_blocks(difficulty, duration)
        when "corrida"  then run_blocks(difficulty, duration)
        when "caminhada" then walk_blocks(difficulty, duration)
        when "hiit", "cardio" then hiit_blocks(difficulty, duration)
        else hiit_blocks(difficulty, duration)
        end
      end

      def bike_blocks(difficulty, _duration)
        case difficulty
        when "iniciante"
          [
            session_block(1, "Aquecimento — Bike", "Pedale em ritmo confortável para aquecer.", 5, "leve", "bike"),
            session_block(2, "Pedalada Contínua", "Mantenha ritmo moderado e constante.", 10, "moderado", "bike"),
            session_block(3, "Desaquecimento — Bike", "Reduza o ritmo gradualmente.", 5, "leve", "bike"),
          ]
        when "intenso"
          blocks = [session_block(1, "Aquecimento — Bike", "Pedale suave para ativar as pernas.", 10, "leve", "bike")]
          10.times do |i|
            blocks << session_block(blocks.size + 1, "Sprint #{i + 1}", "Pedale no máximo esforço.", 1, "intenso", "bike")
            blocks << session_block(blocks.size + 1, "Recuperação #{i + 1}", "Pedale leve para recuperar.", 2, "leve", "bike") unless i == 9
          end
          blocks << session_block(blocks.size + 1, "Desaquecimento — Bike", "Reduza o ritmo gradualmente.", 10, "leve", "bike")
          blocks
        else # moderado
          blocks = [session_block(1, "Aquecimento — Bike", "Pedale em ritmo leve.", 5, "leve", "bike")]
          8.times do |i|
            blocks << session_block(blocks.size + 1, "Intervalo Forte #{i + 1}", "Aumente a intensidade por 30 segundos.", 1, "intenso", "bike")
            blocks << session_block(blocks.size + 1, "Recuperação #{i + 1}", "Volte ao ritmo moderado por 90 segundos.", 2, "leve", "bike") unless i == 7
          end
          blocks << session_block(blocks.size + 1, "Desaquecimento — Bike", "Reduza o ritmo gradualmente.", 5, "leve", "bike")
          blocks
        end
      end

      def run_blocks(difficulty, _duration)
        case difficulty
        when "iniciante"
          [
            session_block(1, "Aquecimento — Caminhada", "Caminhe em ritmo confortável.", 5, "leve", "corrida"),
            session_block(2, "Corrida Contínua", "Corra em ritmo que permita conversar.", 15, "moderado", "corrida"),
            session_block(3, "Desaquecimento", "Volte a caminhar suavemente.", 5, "leve", "corrida"),
          ]
        when "intenso"
          blocks = [session_block(1, "Aquecimento — Caminhada", "Caminhe em ritmo leve.", 10, "leve", "corrida")]
          8.times do |i|
            blocks << session_block(blocks.size + 1, "Tiro #{i + 1}", "Corra no limite de velocidade.", 1, "intenso", "corrida")
            blocks << session_block(blocks.size + 1, "Trote #{i + 1}", "Recupere trotando suavemente.", 2, "leve", "corrida") unless i == 7
          end
          blocks << session_block(blocks.size + 1, "Desaquecimento", "Caminhe para recuperar.", 5, "leve", "corrida")
          blocks
        else # moderado
          blocks = [session_block(1, "Aquecimento — Caminhada", "Caminhe por 5 minutos.", 5, "leve", "corrida")]
          6.times do |i|
            blocks << session_block(blocks.size + 1, "Corrida #{i + 1}", "Corra em ritmo moderado a forte.", 3, "moderado", "corrida")
            blocks << session_block(blocks.size + 1, "Caminhada #{i + 1}", "Recupere caminhando por 90 segundos.", 2, "leve", "corrida") unless i == 5
          end
          blocks << session_block(blocks.size + 1, "Desaquecimento", "Caminhe para desacelerar.", 5, "leve", "corrida")
          blocks
        end
      end

      def walk_blocks(difficulty, duration)
        case difficulty
        when "iniciante"
          [
            session_block(1, "Caminhada Leve", "Caminhe em ritmo confortável, focando na respiração.", duration, "leve", "caminhada"),
          ]
        when "intenso"
          [
            session_block(1, "Aquecimento", "Caminhe devagar para ativar o corpo.", 5, "leve", "caminhada"),
            session_block(2, "Caminhada Rápida", "Aumente o ritmo — caminhe com passadas largas e braços ativos.", duration - 10, "intenso", "caminhada"),
            session_block(3, "Desaquecimento", "Reduza gradualmente o ritmo.", 5, "leve", "caminhada"),
          ]
        else
          [
            session_block(1, "Aquecimento", "Comece em ritmo leve.", 5, "leve", "caminhada"),
            session_block(2, "Caminhada Moderada", "Mantenha ritmo constante e respiração controlada.", duration - 10, "moderado", "caminhada"),
            session_block(3, "Desaquecimento", "Reduza o ritmo nos últimos minutos.", 5, "leve", "caminhada"),
          ]
        end
      end

      def hiit_blocks(difficulty, _duration)
        work_secs, rest_secs, rounds = case difficulty
                                       when "iniciante" then [30, 30, 8]
                                       when "intenso"   then [45, 15, 12]
                                       else [40, 20, 10]
                                       end
        blocks = [session_block(1, "Aquecimento HIIT", "Mobilize as articulações e eleve a frequência cardíaca.", 5, "leve", "hiit")]
        rounds.times do |i|
          blocks << session_block(blocks.size + 1, "Bloco #{i + 1} — Trabalho", "Esforço máximo por #{work_secs}s.", work_secs / 60.0, "intenso", "hiit")
          blocks << session_block(blocks.size + 1, "Bloco #{i + 1} — Descanso", "Respire e recupere.", rest_secs / 60.0, "leve", "hiit") unless i == rounds - 1
        end
        blocks << session_block(blocks.size + 1, "Resfriamento", "Volte ao estado de repouso gradualmente.", 5, "leve", "hiit")
        blocks
      end

      def session_block(idx, name, description, duration_minutes, intensity, exercise_type)
        {
          workout_day_exercise_id: -idx,
          exercise_id: nil,
          name: name,
          muscle_group: nil,
          exercise_type: exercise_type,
          description: description,
          instructions: description,
          image_url: "/exercise-images/#{exercise_type}.svg",
          gif_url: nil,
          video_url: nil,
          muscle_image_url: "/muscle-images/cardio.svg",
          sets: nil,
          reps: nil,
          rest_seconds: nil,
          duration_minutes: duration_minutes.ceil,
          intensity: intensity,
          order_index: idx - 1,
          is_favorite: false,
          last_performed_at: nil,
        }
      end

      # ── Exercise-based workouts ─────────────────────────────────────────────

      def build_exercises(modality, muscle_groups, location, exercise_count, fav_ids)
        exercise_type = MODALITY_TO_EXERCISE_TYPE[modality]

        if exercise_type
          scope = Exercise.where(exercise_type: exercise_type)
          scope = apply_location_filter(scope, location)
          fav_priority = fav_ids.any? ? Arel.sql("CASE WHEN id IN (#{fav_ids.map(&:to_i).join(',')}) THEN 0 ELSE 1 END") : Arel.sql("1")
          scope = scope.order(fav_priority, gif_presence_order, :id)
          scope.limit(exercise_count).to_a
        else
          chosen = []
          per_group = [(exercise_count.to_f / muscle_groups.size).ceil, 1].max
          muscle_groups.each do |group|
            group_scope = Exercise.where(exercise_type: "musculacao", muscle_group: group)
            group_scope = apply_location_filter(group_scope, location)
            fav_priority = fav_ids.any? ? Arel.sql("CASE WHEN id IN (#{fav_ids.map(&:to_i).join(',')}) THEN 0 ELSE 1 END") : Arel.sql("1")
            group_scope = group_scope.order(fav_priority, gif_presence_order, :id).limit(per_group)
            chosen.concat(group_scope.to_a)
            break if chosen.size >= exercise_count
          end
          chosen.first(exercise_count)
        end
      end

      def apply_location_filter(scope, location)
        case location
        when "casa" then scope.where(home_compatible: true)
        when "ar_livre" then scope.where(equipment_type: OUTDOOR_EQUIPMENT)
        else scope
        end
      end

      def gif_presence_order
        Arel.sql("CASE WHEN gif_url IS NOT NULL THEN 0 ELSE 1 END")
      end

      def workout_name(modality, groups, difficulty)
        modality_labels = {
          "musculacao"  => "Musculação",
          "funcional"   => "Funcional",
          "corrida"     => "Corrida",
          "bike"        => "Bike",
          "cardio"      => "Cardio",
          "caminhada"   => "Caminhada",
          "mobilidade"  => "Mobilidade",
          "alongamento" => "Alongamento",
          "hiit"        => "HIIT",
        }
        difficulty_label = case difficulty
                           when "iniciante" then "Iniciante"
                           when "intenso"   then "Intenso"
                           else "Moderado"
                           end
        modality_label = modality_labels[modality] || "Full Body"
        "Treino Rápido — #{modality_label} #{difficulty_label}"
      end
    end
  end
end

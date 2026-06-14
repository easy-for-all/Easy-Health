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

      MODALITY_TO_EXERCISE_TYPE = {
        "musculacao"  => "musculacao",
        "funcional"   => "funcional",
        "corrida"     => "cardio",
        "bike"        => "cardio",
        "cardio"      => "cardio",
        "caminhada"   => "cardio",
        "mobilidade"  => "funcional",
        "alongamento" => "funcional",
      }.freeze

      CARDIO_MODALITIES = %w[corrida bike cardio caminhada].freeze
      STRENGTH_MODALITIES = %w[musculacao funcional mobilidade alongamento].freeze

      def create
        duration   = params[:duration_minutes].to_i.clamp(10, 90)
        difficulty = params[:difficulty].presence || "moderado"
        location   = params[:location].presence || "academia"
        modality   = params[:modality].presence || "ai_choice"

        raw_groups     = Array(params[:muscle_groups]).map(&:presence).compact
        muscle_groups  = raw_groups.any? ? raw_groups : ALL_MUSCLE_GROUPS

        exercise_count = (duration / 8.0).round.clamp(3, 12)
        params_sr      = DIFFICULTY_PARAMS[difficulty] || DIFFICULTY_PARAMS["moderado"]

        fav_ids = current_user.user_favorite_exercises.pluck(:exercise_id)

        chosen_exercises = build_exercises(modality, muscle_groups, location, exercise_count, fav_ids)

        render json: {
          day: {
            id: nil,
            name: workout_name(modality, muscle_groups, difficulty),
            quick: true,
            exercises: chosen_exercises.each_with_index.map do |ex, idx|
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
                sets: params_sr[:sets],
                reps: params_sr[:reps],
                rest_seconds: params_sr[:rest_seconds],
                duration_minutes: nil,
                intensity: nil,
                order_index: idx,
                is_favorite: fav_ids.include?(ex.id),
                last_performed_at: nil
              }
            end
          }
        }, status: :created
      end

      private

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

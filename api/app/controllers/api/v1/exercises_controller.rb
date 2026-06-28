module Api
  module V1
    class ExercisesController < BaseController
      before_action :require_active_access!, only: [:intelligent_suggestions, :ai_substitute]

      def index
        favorite_ids = Set.new(current_user.user_favorite_exercises.pluck(:exercise_id))

        exercises = Exercise.browseable
        exercises = exercises.where(muscle_group: params[:muscle_group]) if params[:muscle_group].present?
        exercises = exercises.where(exercise_type: params[:exercise_type]) if params[:exercise_type].present?
        exercises = exercises.where(equipment_type: params[:equipment_type]) if params[:equipment_type].present?
        if params[:name].present?
          exercises = exercises.where(
            "unaccent(name) ILIKE unaccent(:t) OR unaccent(name_en) ILIKE unaccent(:t) OR unaccent(description) ILIKE unaccent(:t)",
            t: "%#{params[:name]}%"
          )
        end

        if params[:only_favorites] == "true"
          exercises = exercises.where(id: favorite_ids.to_a)
        end

        if params[:exclude_ids].present?
          exclude = params[:exclude_ids].to_s.split(",").map(&:to_i).select(&:positive?)
          exercises = exercises.where.not(id: exclude)
        end

        sorted = exercises.sort_by { |e| favorite_ids.include?(e.id) ? 0 : 1 }

        render json: sorted.map { |e| exercise_json(e, favorite_ids) }
      end

      def setup_guide
        exercise = Exercise.find(params[:id])
        guide = exercise.setup_guide.presence || ExerciseSetupGuideService.new(exercise).call
        if guide
          render json: { setup_guide: guide }
        else
          render json: { error: "Não foi possível gerar o guia" }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Exercise not found" }, status: :not_found
      end

      def ai_substitute
        unless params[:image].present?
          return render json: { error: "No image provided" }, status: :unprocessable_entity
        end

        file     = params[:image]
        exercise = Exercise.find(params[:exercise_id])

        result = ExerciseSubstituteService.new(
          image_data:   file.read,
          content_type: file.content_type,
          exercise:     exercise,
          user:         current_user
        ).call

        if result.nil?
          return render json: { error: "Não foi possível identificar o aparelho. Tente com outra foto." }, status: :unprocessable_entity
        end

        render json: result
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Exercise not found" }, status: :not_found
      end

      def intelligent_suggestions
        current_exercise = Exercise.find_by(id: params[:current_exercise_id])
        user_text        = params[:user_text].to_s.strip
        already_ids      = params[:already_suggested_ids].to_s.split(",").map(&:to_i).compact

        return render json: { error: "current_exercise_id required" }, status: :unprocessable_entity unless current_exercise

        intent = ExerciseIntelligenceService.parse_user_intent(user_text)

        if intent[:intent_type] == "ambiguous" && Ai::OpenaiCoachService.enabled?
          openai = Ai::OpenaiCoachService.new(current_user)
          ai_intent = openai.parse_intent(user_text, {
            exercise_name: current_exercise.name,
            muscle_group:  current_exercise.muscle_group,
          })
          intent = ai_intent.deep_symbolize_keys if ai_intent.is_a?(Hash) && ai_intent["intent_type"].present?
        end

        ranked = ExerciseIntelligenceService.rank_replacement_exercises(
          user:                  current_user,
          current_exercise:      current_exercise,
          intent:                intent,
          already_suggested_ids: already_ids,
        )

        per_page = (params[:per_page] || 5).to_i
        results  = ranked.first(per_page)

        if results.empty? && ranked.empty?
          return render json: {
            exercises:    [],
            intent:       intent,
            message:      "Não encontrei novas opções boas com esse critério. Posso ampliar para exercícios parecidos?",
            no_more:      true,
          }
        end

        favorite_ids = Set.new(current_user.user_favorite_exercises.pluck(:exercise_id))

        render json: {
          exercises: results.map { |r| exercise_suggestion_json(r[:exercise], r[:reason], r[:score], favorite_ids) },
          intent:    intent,
          no_more:   false,
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Exercise not found" }, status: :not_found
      end

      def suggestion_feedback
        exercise   = Exercise.find(params[:id])
        event_type = params[:event_type].to_s
        current_id = params[:current_exercise_id].to_i

        unless ExerciseSuggestionLog::EVENT_TYPES.include?(event_type)
          return render json: { error: "Invalid event_type" }, status: :unprocessable_entity
        end

        log = ExerciseSuggestionLog.create!(
          user:                   current_user,
          current_exercise_id:    current_id.positive? ? current_id : nil,
          suggested_exercise_id:  exercise.id,
          event_type:             event_type,
          intent_text:            params[:intent_text],
          parsed_intent:          params[:parsed_intent] || {},
          score:                  params[:score],
          accepted:               event_type == "suggestion_accepted",
        )

        if event_type == "suggestion_accepted" && params[:preference_key].present?
          UserTrainingPreference.set(
            user:       current_user,
            key:        params[:preference_key],
            value:      params[:preference_value].to_s,
            source:     "swap_feedback",
            confidence: 0.9,
          )
        end

        render json: { logged: true, id: log.id }, status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Exercise not found" }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      include ExerciseImageHelper

      def exercise_json(exercise, favorite_ids = Set.new)
        {
          id:              exercise.id,
          name:            exercise.name,
          name_en:         exercise.name_en,
          muscle_group:    exercise.muscle_group,
          exercise_type:   exercise.exercise_type,
          equipment_type:  exercise.equipment_type,
          description:     exercise.description,
          instructions:    exercise.instructions,
          image_url:       exercise_image_url(exercise),
          gif_url:         exercise.gif_url,
          video_url:       exercise.video_url,
          muscle_image_url: muscle_image_url(exercise.muscle_group),
          is_favorite:     favorite_ids.include?(exercise.id),
        }
      end

      def exercise_suggestion_json(exercise, reason, score, favorite_ids = Set.new)
        exercise_json(exercise, favorite_ids).merge(
          reason: reason,
          score:  score,
        )
      end
    end
  end
end

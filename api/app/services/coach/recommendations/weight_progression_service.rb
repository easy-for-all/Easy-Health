module Coach
  module Recommendations
    class WeightProgressionService
      RECOMMENDATION_TYPE = "weight_progression"

      def initialize(user:)
        @user = user
      end

      def call
        active_plan = @user.workout_plans.find_by(active: true)
        return unless active_plan

        exercise_ids = active_plan.workout_days
          .joins(workout_day_exercises: :exercise)
          .where(exercises: { exercise_type: "musculacao" })
          .pluck("exercises.id")
          .uniq

        exercise_ids.each { |id| try_create_recommendation(id) }
      end

      private

      def try_create_recommendation(exercise_id)
        return if pending_exists?(exercise_id)

        result = LoadProgressionService.new(user: @user, exercise_id: exercise_id).call
        return unless result[:action] == "increase" && result[:suggested_weight].present?
        return if already_planned?(exercise_id, result[:suggested_weight])

        exercise = Exercise.find_by(id: exercise_id)
        return unless exercise

        CoachRecommendation.create!(
          user:                @user,
          exercise:            exercise,
          recommendation_type: RECOMMENDATION_TYPE,
          status:              "pending",
          title:               "Progressão sugerida",
          message:             build_message(exercise.name, result[:current_weight], result[:suggested_weight]),
          exercise_name:       exercise.name,
          current_value:       result[:current_weight],
          recommended_value:   result[:suggested_weight],
          unit:                "kg",
          confidence:          calculate_confidence(exercise_id),
          reasons:             build_reasons
        )
      rescue ActiveRecord::RecordInvalid
        nil
      end

      def pending_exists?(exercise_id)
        CoachRecommendation.for_user(@user)
          .where(exercise_id: exercise_id, recommendation_type: RECOMMENDATION_TYPE)
          .where(
            "status = 'pending' OR (status = 'accepted' AND accepted_at > ?)",
            7.days.ago
          )
          .exists?
      end

      def already_planned?(exercise_id, suggested_weight)
        return false unless suggested_weight

        active_plan = @user.workout_plans.find_by(active: true)
        return false unless active_plan

        active_plan.workout_days
          .joins(:workout_day_exercises)
          .where(workout_day_exercises: { exercise_id: exercise_id })
          .where("workout_day_exercises.planned_weight >= ?", suggested_weight)
          .exists?
      end

      def session_count(exercise_id)
        relational_session_ids = ExerciseSession
          .joins(:workout_session)
          .where(exercise_id: exercise_id, status: "completed")
          .where(workout_sessions: { user_id: @user.id, status: "completed", completion_status: "completed" })
          .where("workout_sessions.completed_at > ?", 60.days.ago)
          .distinct
          .pluck(:workout_session_id)

        legacy_scope = @user.workout_sessions
          .where(status: "completed", completion_status: "completed")
          .where("exercise_logs @> ?", [{ exercise_id: exercise_id }].to_json)
          .where("completed_at > ?", 60.days.ago)
        legacy_scope = legacy_scope.where.not(id: relational_session_ids) if relational_session_ids.any?

        relational_session_ids.size + legacy_scope.count
      end

      def calculate_confidence(exercise_id)
        case session_count(exercise_id)
        when 2 then 0.70
        when 3 then 0.85
        else        0.90
        end
      end

      def build_message(name, current, suggested)
        "Você concluiu bem #{name} nas últimas sessões. " \
          "Recomendo aumentar de #{format_weight(current)} para #{format_weight(suggested)} na próxima execução."
      end

      def format_weight(value)
        value == value.floor ? "#{value.to_i}kg" : "#{value}kg"
      end

      def build_reasons
        [
          "Carga estável nas últimas sessões",
          "Séries concluídas com consistência",
          "Progressão conservadora para manter segurança"
        ]
      end
    end
  end
end

module Api
  module V1
    module Coach
      class RecommendationsController < ApplicationController
        before_action :authenticate_user!

        def current
          Coach::Recommendations::WeightProgressionService.new(user: current_user).call

          recommendation = CoachRecommendation.for_user(current_user)
            .pending
            .order(confidence: :desc, created_at: :desc)
            .first

          render json: { recommendation: serialize(recommendation) }
        end

        def accept
          recommendation = current_user.coach_recommendations.pending.find(params[:id])

          previous_weight = find_workout_day_exercise(recommendation)&.planned_weight
          apply_planned_weight(recommendation)

          recommendation.accept!(
            previous_planned_weight: previous_weight,
            new_planned_weight:      recommendation.recommended_value,
            accepted_from:           "home_coach_card"
          )

          render json: {
            success:        true,
            message:        "Carga atualizada para #{format_weight(recommendation.recommended_value)} na próxima execução de #{recommendation.exercise_name}.",
            recommendation: serialize(recommendation)
          }
        end

        def dismiss
          recommendation = current_user.coach_recommendations.pending.find(params[:id])
          recommendation.dismiss!
          render json: { success: true, message: "Sugestão ignorada." }
        end

        private

        def find_workout_day_exercise(recommendation)
          return unless recommendation.exercise_id

          active_plan = current_user.workout_plans.find_by(active: true)
          return unless active_plan

          active_plan.workout_days
            .joins(:workout_day_exercises)
            .flat_map(&:workout_day_exercises)
            .find { |wde| wde.exercise_id == recommendation.exercise_id }
        end

        def apply_planned_weight(recommendation)
          wde = find_workout_day_exercise(recommendation)
          wde&.update(planned_weight: recommendation.recommended_value)
        end

        def format_weight(value)
          return value.to_s unless value
          value == value.floor ? "#{value.to_i}kg" : "#{value}kg"
        end

        def serialize(rec)
          return nil unless rec

          {
            id:                rec.id,
            type:              rec.recommendation_type,
            status:            rec.status,
            title:             rec.title,
            message:           rec.message,
            exercise:          rec.exercise ? { id: rec.exercise.id, name: rec.exercise_name } : nil,
            current_value:     rec.current_value,
            recommended_value: rec.recommended_value,
            unit:              rec.unit,
            confidence:        rec.confidence,
            reasons:           rec.reasons,
            actions:           [
              { label: "Ignorar", action: "dismiss" },
              { label: "Aceitar", action: "accept" }
            ]
          }
        end
      end
    end
  end
end

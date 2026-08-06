module Api
  module V1
    module Anonymous
      # Registra um treino executado sem conta.
      #
      # Deliberadamente muito menor que o controller autenticado. O que ficou de
      # fora — PRs, streak, badges, comunidade, progressão de carga, recalibração
      # do perfil — depende de HISTÓRICO da conta, então para um anônimo
      # produziria zeros de qualquer forma. O que ficou é o que precisa
      # sobreviver ao cadastro: que o treino aconteceu.
      class WorkoutSessionsController < BaseController
        # POST /api/v1/anonymous/workout_sessions
        def create
          session = WorkoutSession.new(session_params)
          session.app_installation_id = anonymous_installation.id
          session.completed_at ||= Time.current
          session.status = session.completion_status == "abandoned" ? "cancelled" : "completed"

          # Um workout_day de outro dono não pode ser referenciado: o vínculo
          # viraria um dado cruzado entre instalações no histórico.
          session.workout_day_id = nil unless owns_workout_day?(session.workout_day_id)

          if session.save
            render json: serialize_session(session), status: :created
          else
            render json: { errors: session.errors.full_messages }, status: :unprocessable_entity
          end
        rescue StandardError => e
          Rails.logger.error("[anonymous] session create failed: #{e.class}: #{e.message}")
          render json: { errors: [ "session_create_failed" ] }, status: :unprocessable_entity
        end

        private

        def owns_workout_day?(workout_day_id)
          return false if workout_day_id.blank?

          WorkoutDay.joins(:workout_plan)
                    .where(workout_plans: { app_installation_id: anonymous_installation.id })
                    .exists?(id: workout_day_id)
        end

        def session_params
          params.permit(
            :workout_day_id,
            :source,
            :duration_minutes,
            :notes,
            :completed_at,
            :fatigue_level,
            :completion_status,
            :completion_rate,
            :completed_sets_count,
            :planned_sets_count,
            exercise_logs: [ :exercise_id, :name, :sets, :reps, :weight_kg, :completed ]
          )
        end

        def serialize_session(session)
          {
            id: session.id,
            workout_day_id: session.workout_day_id,
            status: session.status,
            completion_status: session.completion_status,
            duration_minutes: session.duration_minutes,
            completed_at: session.completed_at
          }
        end
      end
    end
  end
end

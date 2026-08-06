module Api
  module V1
    module Anonymous
      # O plano do usuário sem conta. Mesmo shape de resposta do endpoint
      # autenticado — o serializer é literalmente o mesmo concern, para que uma
      # tela nova não descubra na produção que os dois formatos divergiram.
      class WorkoutPlansController < BaseController
        include WorkoutBlockSerialization
        include WorkoutPlanSerialization

        # POST /api/v1/anonymous/workout_plan/generate
        def generate
          result = AnonymousSessions::GeneratePlan.new(anonymous_session, params: generation_params).call

          case result.status
          when :generated
            render json: serialize_plan(result.plan).merge(plans_remaining: result.plans_remaining), status: :created
          when :limit_reached
            # 403 e não 402: não é pagamento, é "esta é a fronteira do que dá
            # para usar sem conta". O cliente mapeia para a tela de cadastro.
            render json: { error: result.error_code, plans_remaining: 0 }, status: :forbidden
          when :unavailable
            render json: { error: result.error_code, retryable: true }, status: :service_unavailable
          else
            render json: { error: result.error_code, retryable: true }, status: :internal_server_error
          end
        end

        # GET /api/v1/anonymous/workout_plan
        def show
          plan = active_plan
          return render json: { error: "no_active_plan" }, status: :not_found if plan.nil?

          render json: serialize_plan(plan)
        end

        # GET /api/v1/anonymous/workout_plan/today
        def today
          plan = active_plan
          return render json: { error: "no_active_plan" }, status: :not_found if plan.nil?

          day = plan.workout_days.find_by(day_of_week: Date.today.wday)
          return render json: { day: nil, message: "Rest day" } if day.nil?

          render json: { day: serialize_day_with_exercises(day) }
        end

        # GET /api/v1/anonymous/workout_days/:id
        def day
          # O escopo é o do dono, não o id cru: sem isto, um token anônimo
          # válido leria o dia de qualquer plano do sistema passando o id.
          day = WorkoutDay.joins(:workout_plan)
                          .where(workout_plans: { app_installation_id: anonymous_installation.id, active: true })
                          .find(params[:id])

          render json: { day: serialize_day_with_exercises(day) }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "workout_not_found" }, status: :not_found
        end

        private

        def plan_owner
          @plan_owner ||= Workouts::InstallationOwner.new(anonymous_installation)
        end

        def active_plan
          plan_owner.plans.find_by(active: true)
        end

        def generation_params
          {
            training_days_per_week: params[:training_days_per_week],
            activity_preferences:   params[:activity_preferences],
            modality:               params[:modality],
            split_type:             params[:split_type],
            cardio_type:            params[:cardio_type],
            cardio_format:          params[:cardio_format],
            custom_splits:          params[:custom_splits],
            training_location:      params[:training_location],
            selected_muscles:       sanitize_selected_muscles(params[:selected_muscles]),
            muscle_priorities:      sanitize_muscle_priorities(params[:muscle_priorities])
          }
        end

        # Mesma sanitização do controller autenticado: só ids dentro de
        # Exercise::MUSCLE_GROUPS entram.
        def sanitize_selected_muscles(raw)
          return nil if raw.nil?

          Array(raw).map(&:to_s) & Exercise::MUSCLE_GROUPS
        end

        def sanitize_muscle_priorities(raw)
          return nil if raw.blank?

          allowed = %w[high normal avoid]
          raw.to_unsafe_h.each_with_object({}) do |(group, priority), acc|
            group = group.to_s
            priority = priority.to_s
            acc[group] = priority if Exercise::MUSCLE_GROUPS.include?(group) && allowed.include?(priority)
          end
        end
      end
    end
  end
end

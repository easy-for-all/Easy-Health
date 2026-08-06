module Api
  module V1
    module Anonymous
      # O que o cliente precisa saber para decidir se ainda pode gerar.
      #
      # O cliente usa isto para não oferecer um botão que o servidor vai
      # recusar — mas é cortesia, não guarda: a autoridade é o 403 de
      # GeneratePlan, e o cliente trata os dois pelo mesmo caminho.
      class StatesController < BaseController
        # GET /api/v1/anonymous/state
        def show
          render json: {
            plans_remaining: anonymous_session.plans_remaining,
            plans_generated_count: anonymous_session.plans_generated_count,
            max_plans: AnonymousOnboardingSession::MAX_PLANS,
            has_active_plan: active_plan_exists?,
            has_profile_answers: anonymous_session.profile_answers.present?
          }
        end

        private

        def active_plan_exists?
          WorkoutPlan.exists?(app_installation_id: anonymous_installation.id, active: true)
        end
      end
    end
  end
end

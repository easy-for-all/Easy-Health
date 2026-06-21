module Api
  module V1
    class AiAgentsController < BaseController
      before_action :require_active_access!

      def personal_trainer
        result = AiAgents::PersonalTrainerService.new(current_user).call
        render json: result
      rescue => e
        Rails.logger.error("[AiAgentsController#personal_trainer] #{e.message}")
        render json: { recommendations: [], message: "Erro ao processar análise." }, status: :internal_server_error
      end

      def conditioning
        result = AiAgents::ConditioningService.new(current_user).call
        render json: result
      rescue => e
        Rails.logger.error("[AiAgentsController#conditioning] #{e.message}")
        render json: { recommendations: [], message: "Erro ao processar análise." }, status: :internal_server_error
      end
    end
  end
end

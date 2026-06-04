module Api
  module V1
    class CoachController < BaseController
      def messages
        messages = Array(params[:messages]).map do |m|
          { role: m[:role].to_s, content: m[:content].to_s }
        end

        context = (params[:context] || {}).permit(
          :screen, :exercise_name, :muscle_group, :set_info
        ).to_h

        reply = AiAgents::CoachService.new(current_user, messages: messages, context: context).call

        if reply.present?
          render json: { reply: reply }
        else
          render json: { reply: "Não consegui processar sua mensagem agora. Tente novamente." },
                 status: :ok
        end
      rescue => e
        Rails.logger.error("[CoachController#messages] #{e.message}")
        render json: { reply: "Erro interno. Tente em alguns segundos." },
               status: :internal_server_error
      end
    end
  end
end

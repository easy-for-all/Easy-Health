module Api
  module V1
    class CoachController < BaseController
      before_action :require_active_access!, only: [:messages]

      DAILY_MESSAGE_LIMIT = 20

      def messages
        user_message = last_user_message

        if ::Ai::CoachScopeGuard.allowed?(user_message) == false
          render json: { reply: ::Ai::CoachScopeGuard::BLOCKED_RESPONSE, blocked: true }
          return
        end

        if daily_limit_reached?
          render json: {
            reply: "Você atingiu o limite diário de #{DAILY_MESSAGE_LIMIT} mensagens do Coach IA. " \
                   "Volte amanhã ou continue usando seu plano de treino no app.",
            limit_reached: true
          }
          return
        end

        messages = Array(params[:messages]).map do |m|
          { role: m[:role].to_s, content: m[:content].to_s }
        end

        context = (params[:context] || {}).permit(
          :screen, :exercise_name, :muscle_group, :set_info
        ).to_h

        training_context = ::Ai::UserTrainingContextBuilder.new(current_user).call

        reply = AiAgents::CoachService.new(
          current_user,
          messages:         messages,
          context:          context,
          training_context: training_context
        ).call

        if reply.present?
          record_coach_usage
          render json: { reply: reply, blocked: false }
        else
          render json: { reply: "Não consegui processar sua mensagem agora. Tente novamente." }
        end
      rescue => e
        Rails.logger.error("[CoachController#messages] #{e.message}")
        render json: { reply: "Erro interno. Tente em alguns segundos." },
               status: :internal_server_error
      end

      private

      def last_user_message
        Array(params[:messages]).reverse.find { |m| m[:role].to_s == "user" }&.dig(:content).to_s
      end

      def daily_limit_reached?
        current_user.ai_usage_logs
                    .where(task_type: "coach_chat", status: "success")
                    .where(created_at: Time.current.beginning_of_day..)
                    .count >= DAILY_MESSAGE_LIMIT
      end

      def record_coach_usage
        cfg = AiConfig.for(:coach_chat)
        AiUsageLog.create!(
          user:      current_user,
          task_type: "coach_chat",
          model:     cfg[:model],
          status:    "success"
        )
      rescue => e
        Rails.logger.error("[CoachController] failed to log usage: #{e.message}")
      end
    end
  end
end

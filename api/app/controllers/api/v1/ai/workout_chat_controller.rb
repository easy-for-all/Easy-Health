module Api
  module V1
    module Ai
      class WorkoutChatController < Api::V1::BaseController
        MAX_MESSAGE_LENGTH = ENV.fetch("AI_WORKOUT_CHAT_MAX_MESSAGE_LENGTH", "1500").to_i
        FALLBACK_PREVIEW_REPLY = "Não consegui personalizar 100% com a IA agora, então preparei um treino seguro " \
                                  "baseado no seu perfil. Você pode ajustar quando quiser."

        before_action :require_active_access!
        before_action :load_active_conversation, only: [:message]
        before_action :load_any_recent_conversation, only: [:confirm]

        def start
          conversation = ::AiWorkoutChatConversation.active_for(current_user).first
          is_new = conversation.nil?
          conversation ||= create_conversation

          UserEventService.track(user: current_user, event: :ai_workout_chat_started) if is_new

          render json: {
            status:             conversation.status,
            reply:              greeting_for(conversation),
            collected_profile:  conversation.collected_profile
          }
        end

        def message
          text = params[:message].to_s.strip
          return render_error("message obrigatória") if text.blank?
          if text.length > MAX_MESSAGE_LENGTH
            return render_error("mensagem muito longa (máximo #{MAX_MESSAGE_LENGTH} caracteres)")
          end

          check_rate_limit!(:workout_chat_message)
          return if performed?

          classification = ::Ai::WorkoutChatScopeGuard.classify(text)
          append_local_message("user", text)

          if classification == :security_abuse
            handle_blocked(classification, ::Ai::WorkoutChatScopeGuard::SECURITY_REFUSAL, :ai_workout_blocked_security)
          elsif classification == :out_of_scope
            handle_blocked(classification, ::Ai::WorkoutChatScopeGuard::OUT_OF_SCOPE_REFUSAL, :ai_workout_blocked_out_of_scope)
          elsif @conversation.status == "previewing"
            handle_adjustment(text)
          else
            handle_collecting_turn(text, classification)
          end
        rescue => e
          Rails.logger.error("[Api::V1::Ai::WorkoutChatController#message] #{e.message}")
          UserEventService.track(user: current_user, event: :ai_workout_creation_failed, metadata: { stage: "message", error: e.message })
          render json: { reply: "Erro interno. Tente novamente em alguns segundos." }, status: :internal_server_error
        end

        def confirm
          if @conversation.status == "confirmed"
            return render json: { status: "confirmed", workout_plan_id: @conversation.workout_plan_id }
          end

          unless @conversation.status == "previewing"
            return render_error("no_preview_to_confirm")
          end

          result = ::AiWorkoutChat::ConfirmService.new(@conversation).call

          if result.success?
            UserEventService.track(user: current_user, event: :ai_workout_confirmed,
                                    metadata: { workout_plan_id: result.workout_plan_id })
            render json: { status: "confirmed", workout_plan_id: result.workout_plan_id }, status: :created
          else
            UserEventService.track(user: current_user, event: :ai_workout_creation_failed,
                                    metadata: { stage: "confirm", error: result.error })
            render_error("Não conseguimos montar seu treino agora. Ajuste as preferências e tente novamente.")
          end
        rescue => e
          Rails.logger.error("[Api::V1::Ai::WorkoutChatController#confirm] #{e.message}")
          render json: { error: "Erro interno. Tente novamente em alguns segundos." }, status: :internal_server_error
        end

        private

        def load_active_conversation
          @conversation = ::AiWorkoutChatConversation.active_for(current_user).first
          render_error("no_active_conversation") unless @conversation
        end

        def load_any_recent_conversation
          @conversation = ::AiWorkoutChatConversation.where(user: current_user).order(created_at: :desc).first
          render_error("no_active_conversation") unless @conversation
        end

        def create_conversation
          ::AiWorkoutChatConversation.create!(
            user:              current_user,
            status:            "collecting",
            collected_profile: seed_profile
          )
        end

        def seed_profile
          profile = current_user.health_profile
          return {} unless profile

          {
            "goal"                     => profile.goal,
            "fitness_level"            => profile.fitness_level,
            "training_days_per_week"   => profile.training_days_per_week,
            "training_location"        => profile.training_location,
            "available_equipment"      => profile.available_equipment,
            "limitations"              => profile.limitations,
            "session_duration_minutes" => profile.session_duration_minutes,
            "modality"                 => profile.modality
          }.compact
        end

        def greeting_for(conversation)
          if ::Ai::WorkoutChatReadiness.ready?(conversation.collected_profile)
            "Já sei bastante sobre o seu perfil! Me conta se quer ajustar algo, ou já posso montar uma prévia do seu treino."
          elsif conversation.collected_profile.present?
            "Já tenho algumas informações suas. Me conta sua rotina, objetivo e limitações que eu monto um treino para você."
          else
            "Conte sua rotina, objetivo e limitações. A EasyHealth monta um treino para você."
          end
        end

        def append_local_message(role, content)
          @conversation.messages = Array(@conversation.messages) + [
            { role: role, content: content, created_at: Time.current.iso8601 }
          ]
        end

        def bump_guardrail_flag(key)
          flags = @conversation.guardrail_flags || {}
          flags[key] = flags[key].to_i + 1
          @conversation.guardrail_flags = flags
        end

        def handle_blocked(classification, refusal_text, event_name)
          counter_key = classification == :security_abuse ? "security_abuse_count" : "out_of_scope_count"
          bump_guardrail_flag(counter_key)
          append_local_message("assistant", refusal_text)
          @conversation.save!

          AiUsageLog.create!(user: current_user, task_type: "workout_chat_message", model: "n/a", status: classification.to_s)
          UserEventService.track(user: current_user, event: event_name)

          render json: { status: @conversation.status, reply: refusal_text, blocked: true, block_reason: classification.to_s }
        end

        def handle_collecting_turn(text, classification)
          result = ::AiAgents::WorkoutChatMessageService.new(
            current_user, conversation: @conversation, message: text, classification: classification
          ).call

          @conversation.collected_profile = (@conversation.collected_profile || {}).merge(result[:extracted_profile] || {})
          append_local_message("assistant", result[:reply])
          bump_guardrail_flag("medical_risk_count") if classification == :medical_risk_needs_disclaimer

          log_ai_usage(:workout_chat_message)
          UserEventService.track(user: current_user, event: :ai_workout_message_sent)

          ready = result[:ready_for_plan] ||
                  ::Ai::WorkoutChatReadiness.ready?(@conversation.collected_profile) ||
                  @conversation.follow_up_rounds >= 2

          unless ready
            @conversation.follow_up_rounds += 1
            @conversation.save!
            return render json: {
              status:             @conversation.status,
              reply:              result[:reply],
              collected_profile:  @conversation.collected_profile,
              follow_up_rounds:   @conversation.follow_up_rounds,
              blocked:            false
            }
          end

          @conversation.save!
          generate_preview
        end

        def generate_preview
          check_rate_limit!(:workout_chat_plan)
          return if performed?

          result = ::AiAgents::WorkoutChatPlanService.new(
            current_user, collected_profile: @conversation.collected_profile
          ).call

          @conversation.generated_preview = result[:data].as_json
          @conversation.status = "previewing"
          reply = result[:fallback] ? FALLBACK_PREVIEW_REPLY : "Preparei uma prévia do seu treino! Dá uma olhada e me diga se quer ajustar algo ou já pode confirmar."
          append_local_message("assistant", reply)
          @conversation.save!

          log_ai_usage(:workout_chat_plan_generation)
          UserEventService.track(user: current_user, event: :ai_workout_preview_generated, metadata: { fallback: result[:fallback] })

          render json: {
            status:             "previewing",
            reply:              reply,
            preview:            @conversation.generated_preview,
            collected_profile:  @conversation.collected_profile,
            blocked:            false
          }
        end

        def handle_adjustment(text)
          check_rate_limit!(:workout_chat_plan)
          return if performed?

          result = ::AiAgents::WorkoutChatPlanService.new(
            current_user, collected_profile: @conversation.collected_profile,
            previous_preview: @conversation.generated_preview, adjust_instruction: text
          ).call

          @conversation.generated_preview = result[:data].as_json
          reply = result[:fallback] ? FALLBACK_PREVIEW_REPLY : "Ajustei o treino conforme pedido. Confira a nova prévia."
          append_local_message("assistant", reply)
          @conversation.save!

          log_ai_usage(:workout_chat_plan_generation)
          UserEventService.track(user: current_user, event: :ai_workout_preview_adjusted, metadata: { fallback: result[:fallback] })

          render json: {
            status:             "previewing",
            reply:              reply,
            preview:            @conversation.generated_preview,
            collected_profile:  @conversation.collected_profile,
            blocked:            false
          }
        end

        def log_ai_usage(task_key)
          cfg = AiConfig.for(task_key)
          AiUsageLog.create!(user: current_user, task_type: task_key.to_s, model: cfg[:model], status: "success")
        rescue => e
          Rails.logger.error("[Api::V1::Ai::WorkoutChatController] failed to log usage: #{e.message}")
        end
      end
    end
  end
end

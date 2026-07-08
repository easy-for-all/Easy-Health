module AiWorkoutChat
  class ConfirmService
    Result = Struct.new(:success?, :workout_plan_id, :error, keyword_init: true)

    def initialize(conversation)
      @conversation = conversation
      @user         = conversation.user
    end

    def call
      return already_confirmed_result if @conversation.status == "confirmed"

      unless @conversation.status == "previewing" && @conversation.generated_preview.present?
        return error_result("no_preview_to_confirm")
      end

      plan = nil
      WorkoutPlan.transaction do
        plan = WorkoutPlanGeneratorService.new(@user, chat_decision: symbolized_preview).call
        write_back_health_profile
        @conversation.update!(status: "confirmed", workout_plan_id: plan.id, completed_at: Time.current)
      end

      Result.new(success?: true, workout_plan_id: plan.id, error: nil)
    rescue => e
      Rails.logger.error("[AiWorkoutChat::ConfirmService] #{e.message}")
      Result.new(success?: false, workout_plan_id: nil, error: e.message)
    end

    private

    def already_confirmed_result
      Result.new(success?: true, workout_plan_id: @conversation.workout_plan_id, error: nil)
    end

    def error_result(message)
      Result.new(success?: false, workout_plan_id: nil, error: message)
    end

    def symbolized_preview
      @conversation.generated_preview.deep_symbolize_keys
    end

    def write_back_health_profile
      profile = @user.health_profile
      return unless profile

      collected = @conversation.collected_profile || {}
      attrs = %w[goal fitness_level training_days_per_week training_location
                 limitations available_equipment session_duration_minutes modality]
        .index_with { |field| collected[field] }
        .compact

      profile.update!(attrs) if attrs.any?
    rescue => e
      Rails.logger.error("[AiWorkoutChat::ConfirmService] Failed to write back health profile: #{e.message}")
    end
  end
end

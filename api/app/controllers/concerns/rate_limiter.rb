module RateLimiter
  extend ActiveSupport::Concern

  DAILY_LIMITS = {
    "generate_workout"    => 3,
    "update_workout"      => 5,
    "exam_analysis"       => 5,
    "image_analysis"      => 10,
    "workout_chat_message" => 20,
    "workout_chat_plan"    => 3,
    "agent_personal_trainer" => 5,
    "agent_conditioning"     => 5,
    "exercise_substitute"    => 20,
  }.freeze

  TASK_LABELS = {
    "generate_workout"    => "geração de treino",
    "update_workout"      => "ajuste de exercício",
    "exam_analysis"       => "análise de exame",
    "image_analysis"      => "análise de foto corporal",
    "workout_chat_message" => "mensagens do chat de IA",
    "workout_chat_plan"    => "gerações de treino via chat",
    "agent_personal_trainer" => "análise do personal trainer IA",
    "agent_conditioning"     => "análise de condicionamento IA",
    "exercise_substitute"    => "substituição de exercício por foto",
  }.freeze

  def check_rate_limit!(task_type)
    return if current_user.admin?

    key   = task_type.to_s
    env_override = ENV["AI_RATE_LIMIT_#{key.upcase}"]
    limit = env_override.present? ? env_override.to_i : DAILY_LIMITS.fetch(key, Float::INFINITY)
    return if limit == Float::INFINITY

    count = AiUsageLog.where(user: current_user, task_type: key)
                      .where(created_at: Date.current.all_day)
                      .count

    if count >= limit
      label = TASK_LABELS.fetch(key, key)
      render json: {
        error: "Você atingiu o limite diário de #{label} (#{limit}/dia). Tente novamente amanhã."
      }, status: :too_many_requests
    end
  end
end

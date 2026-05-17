module RateLimiter
  extend ActiveSupport::Concern

  DAILY_LIMITS = {
    "generate_workout" => 3,
    "update_workout"   => 5,
    "exam_analysis"    => 5,
    "image_analysis"   => 10,
  }.freeze

  TASK_LABELS = {
    "generate_workout" => "geração de treino",
    "update_workout"   => "ajuste de exercício",
    "exam_analysis"    => "análise de exame",
    "image_analysis"   => "análise de foto corporal",
  }.freeze

  def check_rate_limit!(task_type)
    return if current_user.admin?

    key   = task_type.to_s
    limit = DAILY_LIMITS.fetch(key, Float::INFINITY)
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

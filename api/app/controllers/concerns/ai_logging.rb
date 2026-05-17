module AiLogging
  extend ActiveSupport::Concern

  def log_ai_usage(user:, task_type:, model:, response: nil, error: nil)
    input_tokens  = response&.dig("usage", "input_tokens")
    output_tokens = response&.dig("usage", "output_tokens")

    AiUsageLog.create!(
      user:          user,
      task_type:     task_type.to_s,
      model:         model,
      input_tokens:  input_tokens,
      output_tokens: output_tokens,
      status:        error ? "error" : "success",
      error_summary: error&.message&.truncate(255)
    )
  rescue => e
    Rails.logger.error("AiLogging: failed to save log — #{e.message}")
  end
end

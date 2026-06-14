require "openai"
require "digest"

module Ai
  class OpenaiCoachService
    SCOPE_SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a personal trainer assistant embedded in a fitness app called EasyHealth.
      You ONLY answer questions related to:
      - exercises, workout plans, exercise substitution
      - workout load, sets, reps, rest periods
      - training intensity, difficulty adjustments
      - equipment, training location (home/gym)
      - physical limitations and exercise modifications for common discomfort
      - cardio alternatives (running, cycling, walking, HIIT)
      - fitness goals and progress

      If the user asks anything outside this scope, respond with:
      "Posso te ajudar com treino, exercícios, substituições, carga, descanso e adaptação do plano."

      Always respond in Brazilian Portuguese.
      Return ONLY valid JSON with the exact structure requested. No extra text.
    PROMPT

    INTENT_PROMPT_TEMPLATE = <<~PROMPT.freeze
      Analyze the user's message and return a JSON object identifying their workout intent.

      User message: "%<user_text>s"
      Current exercise: %<exercise_name>s (muscle group: %<muscle_group>s)

      Return JSON with this exact structure:
      {
        "intent_type": "<one of: replace_exercise, replace_with_cardio, same_movement_new_equipment, equipment_unavailable, home_exercise, pain_constraint, reduce_intensity, increase_intensity, use_favorite, request_more_options, general_swap>",
        "target_activity": "<bike|running|walking|cardio|hiit|null>",
        "target_muscle": "<chest|back|shoulders|biceps|triceps|legs|core|glutes|calves|null>",
        "target_equipment": "<rope|cable|barbell|dumbbell|machine|bodyweight|band|null>",
        "avoid_equipment": "<same canonical values or null>",
        "location": "<home|gym|outdoor|null>",
        "intensity": "<lighter|heavier|null>",
        "constraint": "<shoulder_pain|knee_pain|lower_back_pain|wrist_pain|pain|null>",
        "user_message_summary": "<one sentence in Portuguese summarizing the user's request>"
      }
    PROMPT

    def initialize(user)
      @user = user
    end

    def self.enabled?
      ENV["OPENAI_ENABLED"] != "false" && ENV["OPENAI_API_KEY"].present?
    end

    def within_daily_limit?
      limit = daily_call_limit
      count = AiUsageLog
                .where(user: @user, provider: "openai")
                .where(created_at: Date.current.all_day)
                .count
      count < limit
    end

    def parse_intent(user_text, context = {})
      return nil unless self.class.enabled?
      return nil unless within_daily_limit?

      cache_key = "openai_intent:#{@user.id}:#{Digest::MD5.hexdigest(user_text.to_s)}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      exercise_name  = context[:exercise_name] || "unknown"
      muscle_group   = context[:muscle_group]  || "unknown"
      model          = AiConfig.for(:openai_intent)[:model]

      prompt = format(
        INTENT_PROMPT_TEMPLATE,
        user_text:     user_text,
        exercise_name: exercise_name,
        muscle_group:  muscle_group,
      )

      response = call_api(
        model:    model,
        messages: [
          { role: "system", content: SCOPE_SYSTEM_PROMPT },
          { role: "user",   content: prompt },
        ],
        max_tokens: AiConfig.for(:openai_intent)[:max_tokens],
      )

      return nil if response.nil?

      parsed = JSON.parse(response["content"])
      register_usage(
        model:        model,
        input_tokens: response["input_tokens"],
        output_tokens: response["output_tokens"],
        feature:      "exercise_intent",
      )

      Rails.cache.write(cache_key, parsed, expires_in: 10.minutes)
      parsed
    rescue JSON::ParserError, KeyError, StandardError => e
      Rails.logger.warn("[OpenAICoachService] parse_intent failed: #{e.message}")
      nil
    end

    private

    def daily_call_limit
      if @user.paid_plan?
        ENV.fetch("OPENAI_DAILY_CALL_LIMIT_PAID", 50).to_i
      else
        ENV.fetch("OPENAI_DAILY_CALL_LIMIT_FREE", 10).to_i
      end
    end

    def daily_token_limit
      if @user.paid_plan?
        ENV.fetch("OPENAI_DAILY_TOKEN_LIMIT_PAID", 100_000).to_i
      else
        ENV.fetch("OPENAI_DAILY_TOKEN_LIMIT_FREE", 20_000).to_i
      end
    end

    def call_api(model:, messages:, max_tokens: 256)
      client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
      response = client.chat(
        parameters: {
          model:      model,
          messages:   messages,
          max_tokens: max_tokens,
        }
      )

      choice = response.dig("choices", 0, "message", "content")
      return nil if choice.blank?

      {
        "content"       => choice.strip,
        "input_tokens"  => response.dig("usage", "prompt_tokens").to_i,
        "output_tokens" => response.dig("usage", "completion_tokens").to_i,
      }
    rescue Faraday::Error, OpenAI::Error => e
      Rails.logger.error("[OpenAICoachService] API call failed: #{e.message}")
      nil
    end

    def register_usage(model:, input_tokens:, output_tokens:, feature:)
      cost = estimate_cost_cents(model, input_tokens, output_tokens)
      AiUsageLog.create!(
        user:                @user,
        provider:            "openai",
        task_type:           feature,
        model:               model,
        input_tokens:        input_tokens,
        output_tokens:       output_tokens,
        status:              "success",
        estimated_cost_cents: cost,
      )
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[OpenAICoachService] register_usage failed: #{e.message}")
    end

    def estimate_cost_cents(model, input_tokens, output_tokens)
      # gpt-4.1-mini pricing (approximate): $0.40/1M input, $1.60/1M output
      input_cost  = (input_tokens  / 1_000_000.0) * 0.40
      output_cost = (output_tokens / 1_000_000.0) * 1.60
      ((input_cost + output_cost) * 100).ceil
    end
  end
end

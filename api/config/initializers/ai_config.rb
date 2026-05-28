module AiConfig
  DEFAULTS = {
    exam_validation:    { model: "claude-haiku-4-5-20251001", max_tokens: 256  },
    exam_extraction:    { model: "claude-haiku-4-5-20251001", max_tokens: 1024 },
    image_validation:   { model: "claude-haiku-4-5-20251001", max_tokens: 256  },
    image_analysis:     { model: "claude-sonnet-4-6",         max_tokens: 512  },
    exercise_substitute:{ model: "claude-haiku-4-5-20251001", max_tokens: 128  },
    setup_guide:        { model: "claude-haiku-4-5-20251001", max_tokens: 900  },
    workout_generation:     { model: "claude-haiku-4-5-20251001", max_tokens: 512  },
    agent_personal_trainer: { model: "claude-haiku-4-5-20251001", max_tokens: 600  },
    agent_conditioning:     { model: "claude-haiku-4-5-20251001", max_tokens: 500  },
    body_composition:       { model: "claude-sonnet-4-6",         max_tokens: 1200 },
  }.freeze

  def self.for(task)
    model      = ENV.fetch("AI_MODEL_#{task.to_s.upcase}",      DEFAULTS.dig(task, :model))
    max_tokens = ENV.fetch("AI_MAX_TOKENS_#{task.to_s.upcase}", DEFAULTS.dig(task, :max_tokens)).to_i
    { model: model, max_tokens: max_tokens }
  end
end

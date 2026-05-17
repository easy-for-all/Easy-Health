class BodyAnalysisService
  Result = Struct.new(:observation, :data_point, keyword_init: true)

  def initialize(image_data:, content_type:, user:, user_media: nil)
    @image_data   = image_data
    @content_type = content_type
    @user         = user
    @user_media   = user_media
  end

  def call
    client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))
    cfg    = AiConfig.for(:image_analysis)

    prompt = <<~PROMPT
      You are a health and fitness assistant. Analyze this body photo and provide a brief, supportive, non-diagnostic observation.

      Rules:
      - Write in Portuguese (Brazil)
      - Be encouraging and positive
      - Do NOT make medical diagnoses or clinical assessments
      - Do NOT estimate specific body fat percentages or numerical measurements
      - Focus on general physical appearance aspects relevant to fitness (posture, muscle definition, overall physique)
      - Keep it to 2-3 sentences maximum

      Respond ONLY with valid JSON, no markdown:
      {
        "observation": "A foto mostra...",
        "confidence": 0.8
      }
    PROMPT

    response = client.messages(parameters: {
      model:      cfg[:model],
      max_tokens: cfg[:max_tokens],
      messages: [{
        role: "user",
        content: [
          {
            type: "image",
            source: {
              type:       "base64",
              media_type: @content_type,
              data:       Base64.strict_encode64(@image_data)
            }
          },
          { type: "text", text: prompt }
        ]
      }]
    })

    raw  = response.dig("content", 0, "text").to_s.strip
    json = JSON.parse(raw)
    observation = json["observation"].to_s.strip
    confidence  = json["confidence"]

    return Result.new(observation: nil, data_point: nil) if observation.blank?

    dp = @user.health_data_points.create!(
      user_media:   @user_media,
      field_name:   "visual_observation",
      value:        nil,
      unit:         nil,
      source_type:  "body_photo",
      status:       "pending_review",
      confidence:   confidence,
      ai_notes:     observation,
      collected_at: Time.current
    )

    Result.new(observation: observation, data_point: dp)
  rescue => e
    Rails.logger.error("BodyAnalysisService: #{e.message}")
    Result.new(observation: nil, data_point: nil)
  end
end

class BodyCompositionAnalysisService
  Result = Struct.new(:data_point, :composition, keyword_init: true)

  REGIONS = %w[chest abdomen shoulders biceps triceps back glutes quadriceps hamstrings calves].freeze

  def initialize(image_data:, content_type:, user:, user_media: nil)
    @image_data   = image_data
    @content_type = content_type
    @user         = user
    @user_media   = user_media
  end

  def call
    client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))
    cfg    = AiConfig.for(:body_composition)

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

    body_fat   = json["estimatedBodyFatPercentage"]
    confidence = json["confidence"]
    summary    = json["summary"].to_s.strip

    return Result.new(data_point: nil, composition: nil) if summary.blank?

    dp = @user.health_data_points.create!(
      user_media:   @user_media,
      field_name:   "body_composition_map",
      value:        body_fat,
      unit:         body_fat ? "%" : nil,
      source_type:  "body_photo",
      status:       "pending_review",
      confidence:   confidence,
      ai_notes:     summary,
      raw_text:     raw,
      collected_at: Time.current
    )

    Result.new(data_point: dp, composition: json)
  rescue => e
    Rails.logger.error("BodyCompositionAnalysisService: #{e.message}")
    Result.new(data_point: nil, composition: nil)
  end

  private

  def prompt
    regions_list = REGIONS.map { |r| "\"#{r}\"" }.join(", ")

    <<~PROMPT
      You are a fitness assessment AI. Analyze this body photo and provide a structured muscle and body fat composition estimate for each major muscle group.

      RULES:
      - This is for personal fitness tracking only, not medical diagnosis
      - muscleLevel (1-5): 1=no visible muscle, 3=average definition, 5=elite development
      - fatLevel (1-5): 1=very lean, 3=moderate body fat, 5=high fat with little definition
      - confidence: how confident you are given photo quality and angles
      - Write notes in Portuguese (Brazil), brief and constructive
      - If a region is not visible: use muscleLevel=3, fatLevel=3, confidence=0.2, note "Região não visível na foto."
      - Set estimatedBodyFatPercentage to null if photo does not allow estimation

      Include exactly these #{REGIONS.size} regions: #{regions_list}

      Respond ONLY with valid JSON, no markdown:
      {
        "estimatedBodyFatPercentage": <number 5-60 or null>,
        "confidence": <0.0-1.0 overall>,
        "summary": "<2-3 sentences in Portuguese, constructive and encouraging>",
        "regions": [
          {
            "name": "<region>",
            "muscleLevel": <1-5>,
            "fatLevel": <1-5>,
            "confidence": <0.0-1.0>,
            "note": "<brief note in Portuguese>"
          }
        ]
      }
    PROMPT
  end
end

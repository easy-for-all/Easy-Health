class ExerciseSubstituteService
  def initialize(image_data:, content_type:, exercise:, candidates:)
    @image_data   = image_data
    @content_type = content_type
    @exercise     = exercise
    @candidates   = candidates
  end

  def call
    client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))
    list   = @candidates.map { |e| "#{e.id}: #{e.name} (#{e.muscle_group || e.exercise_type})" }.join("\n")
    prompt = <<~PROMPT
      You are a fitness expert. The user wants to substitute the exercise "#{@exercise.name}".
      They sent a photo of equipment or an exercise being performed.
      From the list below, pick up to 3 exercises that best replace "#{@exercise.name}"
      considering what is shown in the photo. Return ONLY a JSON array of integer IDs.
      Example: [12, 7, 3]

      Available exercises:
      #{list}
    PROMPT

    cfg = AiConfig.for(:exercise_substitute)
    response = client.messages(parameters: {
      model:      cfg[:model],
      max_tokens: cfg[:max_tokens],
      messages: [{
        role: "user",
        content: [
          {
            type: "image",
            source: {
              type: "base64",
              media_type: @content_type,
              data: Base64.strict_encode64(@image_data)
            }
          },
          { type: "text", text: prompt }
        ]
      }]
    })

    raw = response.dig("content", 0, "text").to_s
    ids = JSON.parse(raw.match(/\[[\d,\s]+\]/m)&.to_s || "[]").map(&:to_i)
    @candidates.select { |e| ids.include?(e.id) }.first(3)
  rescue => e
    Rails.logger.error("ExerciseSubstituteService: #{e.message}")
    []
  end
end

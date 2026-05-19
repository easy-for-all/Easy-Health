class ExerciseSubstituteService
  include ExerciseImageHelper

  CONFIDENCE_THRESHOLD = 0.7

  def initialize(image_data:, content_type:, exercise:, user:)
    @image_data   = image_data
    @content_type = content_type
    @exercise     = exercise
    @user         = user
  end

  def call
    checksum = Digest::SHA256.hexdigest(@image_data)
    cached = EquipmentIdentification.find_by(image_checksum: checksum)

    identification = if cached&.confidence.to_f >= CONFIDENCE_THRESHOLD
      cached
    else
      call_claude(checksum)
    end

    return nil if identification.nil?

    suggestions = find_suggestions(identification)
    { identification: identification_json(identification), suggestions: suggestions }
  rescue => e
    Rails.logger.error("ExerciseSubstituteService: #{e.message}")
    nil
  end

  private

  def call_claude(checksum)
    client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))
    prompt = <<~PROMPT
      Você é um especialista em fitness. Analise esta imagem e identifique o aparelho ou exercício mostrado.
      O usuário quer substituir o exercício atual: "#{@exercise.name}".
      Responda APENAS com JSON válido, sem texto adicional:
      {
        "equipment_name": "nome do aparelho em inglês",
        "localized_name": "nome do aparelho em português",
        "confidence": 0.0,
        "muscle_groups": ["grupo1", "grupo2"],
        "compatible_with_current_exercise": true,
        "reason": "explicação breve em português",
        "suggested_exercise_names": ["nome1", "nome2", "nome3"]
      }
    PROMPT

    cfg = AiConfig.for(:exercise_substitute)
    response = client.messages(parameters: {
      model:      cfg[:model],
      max_tokens: 512,
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

    raw  = response.dig("content", 0, "text").to_s
    json = JSON.parse(raw.match(/\{.*\}/m)&.to_s || "{}")
    return nil if json.empty?

    EquipmentIdentification.create!(
      user:           @user,
      image_checksum: checksum,
      equipment_name: json["equipment_name"],
      localized_name: json["localized_name"],
      confidence:     json["confidence"].to_f,
      muscle_groups:  Array(json["muscle_groups"]),
      compatible:     json["compatible_with_current_exercise"],
      reason:         json["reason"],
      raw_response:   { suggested_names: Array(json["suggested_exercise_names"]), full: json }
    )
  rescue => e
    Rails.logger.error("ExerciseSubstituteService#call_claude: #{e.message}")
    nil
  end

  def find_suggestions(identification)
    raw = identification.raw_response || {}
    names = raw["suggested_names"] || raw[:suggested_names] || []
    found = names.flat_map do |name|
      Exercise.where("name ILIKE ?", "%#{name}%").limit(2)
    end.uniq.first(3)

    if found.empty? && identification.muscle_groups&.any?
      found = Exercise.where(muscle_group: identification.muscle_groups)
        .where.not(id: @exercise.id)
        .limit(3)
    end

    found.map { |ex| exercise_json(ex) }
  end

  def identification_json(identification)
    {
      equipment_name: identification.equipment_name,
      localized_name: identification.localized_name,
      confidence:     identification.confidence,
      muscle_groups:  identification.muscle_groups,
      compatible:     identification.compatible,
      reason:         identification.reason
    }
  end

  def exercise_json(ex)
    {
      id:               ex.id,
      name:             ex.name,
      muscle_group:     ex.muscle_group,
      exercise_type:    ex.exercise_type,
      description:      ex.description,
      image_url:        exercise_image_url(ex),
      muscle_image_url: muscle_image_url(ex.muscle_group)
    }
  end
end

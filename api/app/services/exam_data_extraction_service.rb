class ExamDataExtractionService
  Result = Struct.new(:data_points, keyword_init: true)

  EXTRACTABLE_FIELDS = {
    "weight_kg"        => { label: "Peso",            unit: "kg"    },
    "height_cm"        => { label: "Altura",           unit: "cm"    },
    "bmi"              => { label: "IMC",              unit: "kg/m²" },
    "body_fat_pct"     => { label: "% Gordura",        unit: "%"     },
    "muscle_mass_kg"   => { label: "Massa Muscular",   unit: "kg"    },
    "glucose_mgdl"     => { label: "Glicose",          unit: "mg/dL" },
    "cholesterol_mgdl" => { label: "Colesterol Total", unit: "mg/dL" },
    "hdl_mgdl"         => { label: "HDL",              unit: "mg/dL" },
    "ldl_mgdl"         => { label: "LDL",              unit: "mg/dL" },
    "triglycerides_mgdl" => { label: "Triglicerídeos", unit: "mg/dL" },
    "blood_pressure_systolic"  => { label: "PA Sistólica",  unit: "mmHg" },
    "blood_pressure_diastolic" => { label: "PA Diastólica", unit: "mmHg" },
    "heart_rate_bpm"   => { label: "Frequência Cardíaca", unit: "bpm" },
    "visceral_fat"     => { label: "Gordura Visceral", unit: nil     },
  }.freeze

  def initialize(file_data:, content_type:, user:, user_media: nil)
    @file_data    = file_data
    @content_type = content_type
    @user         = user
    @user_media   = user_media
  end

  def call
    client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))
    cfg    = AiConfig.for(:exam_extraction)

    field_list = EXTRACTABLE_FIELDS.map { |k, v| "#{k}: #{v[:label]} (#{v[:unit]})" }.join("\n")

    prompt = <<~PROMPT
      You are a health data extractor. Analyze this health document and extract numerical values.

      Extract ONLY values that are explicitly present in the document. Do NOT infer or calculate.
      For each found value, estimate your confidence (0.0–1.0).

      Fields to extract (key: label (unit)):
      #{field_list}

      Respond ONLY with valid JSON, no markdown:
      {
        "extracted": [
          {
            "field_name": "weight_kg",
            "value": 85.5,
            "unit": "kg",
            "confidence": 0.95,
            "raw_text": "Peso: 85,5 kg",
            "ai_notes": null
          }
        ]
      }

      If no fields are found, return: {"extracted": []}
    PROMPT

    response = client.messages(parameters: {
      model:      cfg[:model],
      max_tokens: cfg[:max_tokens],
      messages:   [{ role: "user", content: build_content(prompt) }]
    })

    raw  = response.dig("content", 0, "text").to_s.strip
    json = JSON.parse(raw)
    items = Array(json["extracted"])

    data_points = items.filter_map do |item|
      field = item["field_name"].to_s
      value = item["value"]
      next unless EXTRACTABLE_FIELDS.key?(field) && value.present?

      @user.health_data_points.create!(
        user_media:   @user_media,
        field_name:   field,
        value:        value,
        unit:         item["unit"] || EXTRACTABLE_FIELDS.dig(field, :unit),
        source_type:  "exam",
        status:       "pending_review",
        confidence:   item["confidence"],
        raw_text:     item["raw_text"],
        ai_notes:     item["ai_notes"],
        collected_at: Time.current
      )
    end

    Result.new(data_points: data_points)
  rescue => e
    Rails.logger.error("ExamDataExtractionService: #{e.message}")
    Result.new(data_points: [])
  end

  private

  def build_content(prompt)
    if @content_type == "application/pdf"
      [
        {
          type: "document",
          source: {
            type:       "base64",
            media_type: "application/pdf",
            data:       Base64.strict_encode64(@file_data)
          }
        },
        { type: "text", text: prompt }
      ]
    else
      [
        {
          type: "image",
          source: {
            type:       "base64",
            media_type: @content_type,
            data:       Base64.strict_encode64(@file_data)
          }
        },
        { type: "text", text: prompt }
      ]
    end
  end
end

class ExamValidationService
  Result = Struct.new(:valid, :rejection_reason, keyword_init: true)

  VALID_EXAM_CATEGORIES = %w[
    clinical_exam blood_test urine_test imaging_exam cardiology
    bioimpedance body_composition physical_assessment
    medical_report fitness_evaluation
  ].freeze

  def initialize(file_data:, content_type:)
    @file_data    = file_data
    @content_type = content_type
  end

  def call
    client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))

    prompt = <<~PROMPT
      You are a health document classifier. Analyze the provided file.

      Determine if this document or image is related to health monitoring or physical conditioning:
      - Clinical exams (blood tests, urine tests, imaging)
      - Bioimpedance or body composition assessments
      - Medical reports, lab results, or clinical notes
      - Physical fitness evaluations or performance tests
      - Cardiology exams, ECG, stress tests
      - Any document from a healthcare professional or clinic

      Answer ONLY with valid JSON, no markdown:
      {
        "is_health_exam": true,
        "rejection_reason": null
      }

      If is_health_exam is false, rejection_reason must be a short explanation in Portuguese
      (e.g. "O arquivo não parece ser um exame clínico ou documento de saúde.").
    PROMPT

    messages_content = build_content(prompt)

    cfg = AiConfig.for(:exam_validation)
    response = client.messages(parameters: {
      model:      cfg[:model],
      max_tokens: cfg[:max_tokens],
      messages: [{ role: "user", content: messages_content }]
    })

    raw  = response.dig("content", 0, "text").to_s.strip
    json = JSON.parse(raw)

    Result.new(
      valid:            json["is_health_exam"] == true,
      rejection_reason: json["rejection_reason"]
    )
  rescue => e
    Rails.logger.error("ExamValidationService: #{e.message}")
    # Fail open for availability — allow the upload if AI is unavailable
    Result.new(valid: true, rejection_reason: nil)
  end

  private

  def build_content(prompt)
    if @content_type == "application/pdf"
      [
        {
          type: "document",
          source: {
            type: "base64",
            media_type: "application/pdf",
            data: Base64.strict_encode64(@file_data)
          }
        },
        { type: "text", text: prompt }
      ]
    else
      [
        {
          type: "image",
          source: {
            type: "base64",
            media_type: @content_type,
            data: Base64.strict_encode64(@file_data)
          }
        },
        { type: "text", text: prompt }
      ]
    end
  end
end

class BodyPhotoValidationService
  Result = Struct.new(:has_human_body, :has_face, :face_bbox, :rejection_reason, keyword_init: true)

  def initialize(image_data:, content_type:)
    @image_data   = image_data
    @content_type = content_type
  end

  def call
    client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))

    prompt = <<~PROMPT
      Analyze this image carefully.
      1. Does it contain an identifiable human body (torso, limbs visible)? Answer true or false.
      2. Is there a visible human face in the image? Answer true or false.
      3. If there is a face, provide its bounding box as fractions of the image dimensions (0.0 to 1.0), where (x, y) is the top-left corner. Be generous — expand by ~10% on all sides to ensure the face is fully covered.
      4. If the image does NOT contain a human body, provide a short reason in Portuguese.

      Respond ONLY with valid JSON, no markdown, no explanation:
      {
        "has_human_body": true,
        "has_face": false,
        "face_bbox": null,
        "rejection_reason": null
      }

      If has_human_body is false, rejection_reason must explain why (e.g. "A imagem não contém um corpo humano identificável.").
      If has_face is true, face_bbox must be: {"x": 0.1, "y": 0.0, "w": 0.25, "h": 0.3}
    PROMPT

    cfg = AiConfig.for(:image_validation)
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

    raw  = response.dig("content", 0, "text").to_s.strip
    json = JSON.parse(raw)

    Result.new(
      has_human_body:   json["has_human_body"] == true,
      has_face:         json["has_face"] == true,
      face_bbox:        json["face_bbox"],
      rejection_reason: json["rejection_reason"]
    )
  rescue => e
    Rails.logger.error("BodyPhotoValidationService: #{e.message}")
    # On error, allow the upload but skip face blur (fail open for availability)
    Result.new(has_human_body: true, has_face: false, face_bbox: nil, rejection_reason: nil)
  end
end

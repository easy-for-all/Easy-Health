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
      3. If there is a face, provide its TIGHT bounding box covering only the face/head region (NOT the body). Use fractions of the image dimensions (0.0 to 1.0), where x=horizontal start from left, y=vertical start from top, w=width fraction, h=height fraction. The face_bbox should cover only the head — do NOT include shoulders, torso, or large areas of the body.
      4. If the image does NOT contain a human body, provide a short reason in Portuguese.

      IMPORTANT: face_bbox must be TIGHT around the face/head only. For a typical front-facing body photo where the head occupies the top portion, face_bbox.h should be around 0.15 to 0.25, NOT 0.5 or more.

      Respond ONLY with valid JSON, no markdown, no explanation:
      {
        "has_human_body": true,
        "has_face": false,
        "face_bbox": null,
        "rejection_reason": null
      }

      If has_human_body is false, rejection_reason must explain why (e.g. "A imagem não contém um corpo humano identificável.").
      If has_face is true, face_bbox MUST be provided: {"x": 0.35, "y": 0.02, "w": 0.30, "h": 0.18}
      Never return has_face: true with face_bbox: null.
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
    json = JSON.parse(raw.match(/\{.*\}/m)&.to_s || "{}")

    Result.new(
      has_human_body:   json["has_human_body"] == true,
      has_face:         json["has_face"] == true,
      face_bbox:        json["face_bbox"],
      rejection_reason: json["rejection_reason"]
    )
  rescue => e
    Rails.logger.error("BodyPhotoValidationService error: #{e.message} | raw: #{raw.to_s.truncate(300)}")
    # On error, allow the upload but skip face blur (fail open for availability)
    Result.new(has_human_body: true, has_face: false, face_bbox: nil, rejection_reason: nil)
  end
end

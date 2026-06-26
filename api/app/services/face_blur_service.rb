class FaceBlurService
  # Pixelates the face region in an image using libvips.
  # face_bbox: { "x" => float, "y" => float, "w" => float, "h" => float } (0.0–1.0 fractions)
  # Returns processed image bytes (JPEG) or the original bytes if processing fails.

  EXPANSION = 0.05  # expand detected bbox by 5% on each side (was 10% — too large)
  PIXELATE_FACTOR = 0.04  # scale down to 4% then back up (heavy pixelation)
  FALLBACK_TOP_FRACTION = 0.15  # blur top 15% if bbox unavailable (was 25% — included body)

  def initialize(image_data:, face_bbox:, has_face:)
    @image_data = image_data
    @face_bbox  = face_bbox
    @has_face   = has_face
  end

  def call
    img = Vips::Image.new_from_buffer(@image_data, "")
    w   = img.width
    h   = img.height

    bbox = resolved_bbox(w, h)
    return @image_data unless bbox

    fx, fy, fw, fh = bbox

    # Clamp to image bounds
    fx = [[fx, 0].max, w - 1].min
    fy = [[fy, 0].max, h - 1].min
    fw = [[fw, 1].max, w - fx].min
    fh = [[fh, 1].max, h - fy].min

    # Pixelate: scale way down then back up
    face_region = img.crop(fx, fy, fw, fh)
    small  = face_region.resize(PIXELATE_FACTOR)
    pixelated = small.resize(fw.to_f / small.width, vscale: fh.to_f / small.height)
    result = img.composite2(pixelated, :over, x: fx, y: fy)

    result.write_to_buffer(".jpg[Q=85]")
  rescue => e
    Rails.logger.error("FaceBlurService: #{e.message}")
    @image_data
  end

  private

  def resolved_bbox(img_w, img_h)
    if @face_bbox.present?
      x_frac = @face_bbox["x"].to_f
      y_frac = @face_bbox["y"].to_f
      w_frac = @face_bbox["w"].to_f
      h_frac = @face_bbox["h"].to_f

      # Expand bbox by EXPANSION on all sides
      x_frac = [x_frac - EXPANSION, 0.0].max
      y_frac = [y_frac - EXPANSION, 0.0].max
      w_frac = [w_frac + 2 * EXPANSION, 1.0 - x_frac].min
      h_frac = [h_frac + 2 * EXPANSION, 1.0 - y_frac].min

      [
        (x_frac * img_w).to_i,
        (y_frac * img_h).to_i,
        (w_frac * img_w).to_i,
        (h_frac * img_h).to_i
      ]
    elsif @has_face
      # Fallback: pixelate only the top-center area (head position estimate)
      # Horizontally: center 50% of image width; vertically: top 15%
      fallback_w = (img_w * 0.50).to_i
      fallback_x = ((img_w - fallback_w) / 2).to_i
      [fallback_x, 0, fallback_w, (FALLBACK_TOP_FRACTION * img_h).to_i]
    end
  end
end

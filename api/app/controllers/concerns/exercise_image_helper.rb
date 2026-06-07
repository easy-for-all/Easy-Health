module ExerciseImageHelper
  MUSCLE_SVG_FALLBACK = {
    "glutes"    => "legs",
    "calves"    => "legs",
    "forearms"  => "biceps",
    "trapezius" => "back"
  }.freeze

  GYM_EQUIPMENT_TYPES    = %w[gym dumbbell barbell cable machine].freeze
  OFFICIAL_IMAGE_PREFIXES = %w[/exercise-images/db/ /exercise-images/gifdotreino/].freeze

  def exercise_image_url(exercise)
    if gym_exercise?(exercise)
      official = [exercise.gif_url, exercise.image_url].find { |u| official_local_url?(u) && local_file_exists?(u) }
      official || "/exercise-images/#{exercise.exercise_type || 'treino'}.svg"
    else
      exercise.image_url.presence || exercise.gif_url.presence ||
        "/exercise-images/#{exercise.exercise_type || 'treino'}.svg"
    end
  end

  def muscle_image_url(muscle_group)
    svg = MUSCLE_SVG_FALLBACK[muscle_group] || muscle_group || "cardio"
    "/muscle-images/#{svg}.svg"
  end

  private

  def gym_exercise?(exercise)
    exercise.exercise_type == "musculacao" ||
      GYM_EQUIPMENT_TYPES.include?(exercise.equipment_type)
  end

  def official_local_url?(url)
    url.present? && OFFICIAL_IMAGE_PREFIXES.any? { |prefix| url.start_with?(prefix) }
  end

  def local_file_exists?(url)
    path = Rails.root.join("public", url.delete_prefix("/"))
    File.exist?(path)
  end
end

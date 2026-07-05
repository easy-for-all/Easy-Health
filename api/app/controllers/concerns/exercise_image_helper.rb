module ExerciseImageHelper
  MUSCLE_SVG_FALLBACK = {
    "glutes"    => "legs",
    "calves"    => "legs",
    "forearms"  => "biceps",
    "trapezius" => "back"
  }.freeze

  GYM_EQUIPMENT_TYPES = %w[gym dumbbell barbell cable machine].freeze

  def exercise_image_url(exercise)
    gif = exercise.gif_url
    return gif if official_local_gif?(gif)

    "/exercise-images/#{exercise.exercise_type || 'treino'}.svg"
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

  def official_local_gif?(url)
    Exercise.gifdotreino_url?(url) && local_file_exists?(url)
  end

  def local_file_exists?(url)
    path = Rails.root.join("public", url.delete_prefix("/"))
    File.exist?(path)
  end
end

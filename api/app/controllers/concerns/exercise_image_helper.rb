module ExerciseImageHelper
  MUSCLE_SVG_FALLBACK = {
    "glutes"    => "legs",
    "calves"    => "legs",
    "forearms"  => "biceps",
    "trapezius" => "back"
  }.freeze

  def exercise_image_url(exercise)
    exercise.image_url.presence || "/exercise-images/#{exercise.exercise_type || 'treino'}.svg"
  end

  def muscle_image_url(muscle_group)
    svg = MUSCLE_SVG_FALLBACK[muscle_group] || muscle_group || "cardio"
    "/muscle-images/#{svg}.svg"
  end
end

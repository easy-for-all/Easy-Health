module ExerciseImageHelper
  def exercise_image_url(exercise)
    exercise.image_url.presence || "/exercise-images/#{exercise.exercise_type || 'treino'}.svg"
  end

  def muscle_image_url(muscle_group)
    "/muscle-images/#{muscle_group || 'cardio'}.svg"
  end
end

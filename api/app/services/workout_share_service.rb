class WorkoutShareService
  def initialize(user, workout_day_id, options = {})
    @user = user
    @workout_day_id = workout_day_id
    @visibility = options.fetch(:visibility, "private_link")
    @include_weights = options.fetch(:include_weights, false)
    @include_notes = options.fetch(:include_notes, false)
    @expires_in_days = options[:expires_in_days]
    @title = options[:title]
  end

  def call
    day = find_authorized_day!
    snapshot = build_snapshot(day)

    SharedWorkout.create!(
      owner: @user,
      token: generate_token,
      visibility: @visibility,
      title: @title.presence || day.name,
      snapshot: snapshot,
      include_weights: @include_weights,
      include_notes: @include_notes,
      expires_at: expires_at
    )
  end

  private

  def find_authorized_day!
    WorkoutDay
      .joins(workout_plan: :user)
      .where(workout_plans: { user_id: @user.id })
      .find(@workout_day_id)
  rescue ActiveRecord::RecordNotFound
    raise ActiveRecord::RecordNotFound, "Workout day not found"
  end

  def build_snapshot(day)
    exercises = day.workout_day_exercises.includes(:exercise).order(:order_index).map do |wde|
      entry = {
        exercise_id: wde.exercise.id,
        name: wde.exercise.name,
        muscle_group: wde.exercise.muscle_group,
        exercise_type: wde.exercise.exercise_type,
        sets: wde.sets,
        reps: wde.reps,
        rest_seconds: wde.rest_seconds,
        duration_minutes: wde.duration_minutes,
        intensity: wde.intensity
      }
      entry[:weight_kg] = nil unless @include_weights
      entry
    end

    {
      day_name: day.name,
      exercise_count: exercises.count,
      exercises: exercises,
      shared_at: Time.current.iso8601
    }
  end

  def generate_token
    loop do
      token = SecureRandom.urlsafe_base64(18)
      break token unless SharedWorkout.exists?(token: token)
    end
  end

  def expires_at
    return nil unless @expires_in_days
    @expires_in_days.to_i.days.from_now
  end
end

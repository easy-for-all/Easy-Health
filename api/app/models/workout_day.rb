class WorkoutDay < ApplicationRecord
  belongs_to :workout_plan
  has_many :workout_day_exercises, -> { order(:order_index) }, dependent: :destroy
  has_many :exercises, through: :workout_day_exercises

  DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
  validates :name, presence: true

  def day_name
    DAY_NAMES[day_of_week]
  end

  def invalidate_if_needed!(equivalent_finder: nil)
    exercises_with_ids = workout_day_exercises.includes(:exercise).select { |wde| wde.exercise_id.present? }
    return if exercises_with_ids.empty?

    without_gif = exercises_with_ids.reject { |wde| wde.exercise&.gifdotreino_source? }
    return if without_gif.empty?

    invalid_ratio = without_gif.size.to_f / exercises_with_ids.size

    if invalid_ratio >= 0.3
      update!(invalid_workout_reason: "exercises_without_gif")
    else
      without_gif.each do |wde|
        if equivalent_finder && (equiv = equivalent_finder.call(wde.exercise))
          wde.update!(exercise_id: equiv.id)
        else
          wde.destroy
        end
      end
    end
  end
end

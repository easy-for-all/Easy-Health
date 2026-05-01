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
end

class Exercise < ApplicationRecord
  MUSCLE_GROUPS    = %w[chest back shoulders biceps triceps legs core forearms calves glutes trapezius].freeze
  EXERCISE_TYPES   = %w[musculacao cardio natacao corrida funcional caminhada hiit].freeze
  EQUIPMENT_TYPES  = %w[bodyweight gym dumbbell barbell cable machine cardio].freeze

  has_many :workout_day_exercises, dependent: :destroy

  validates :name,           presence: true
  validates :exercise_type,  presence: true, inclusion: { in: EXERCISE_TYPES }
  validates :muscle_group,   inclusion: { in: MUSCLE_GROUPS }, allow_nil: true
  validates :equipment_type, inclusion: { in: EQUIPMENT_TYPES }, allow_nil: true
end

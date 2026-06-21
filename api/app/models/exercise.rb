class Exercise < ApplicationRecord
  MUSCLE_GROUPS    = %w[chest back shoulders biceps triceps legs core forearms calves glutes trapezius].freeze
  EXERCISE_TYPES   = %w[musculacao cardio natacao corrida funcional caminhada hiit timed].freeze
  EQUIPMENT_TYPES  = %w[bodyweight gym dumbbell barbell cable machine cardio].freeze
  GYM_EQUIPMENT    = %w[gym dumbbell barbell cable machine].freeze
  DIFFICULTY_LEVELS = %w[beginner intermediate advanced].freeze

  has_many :workout_day_exercises, dependent: :destroy

  validates :name,             presence: true
  validates :exercise_type,    presence: true, inclusion: { in: EXERCISE_TYPES }
  validates :muscle_group,     inclusion: { in: MUSCLE_GROUPS }, allow_nil: true
  validates :equipment_type,   inclusion: { in: EQUIPMENT_TYPES }, allow_nil: true
  validates :difficulty_level, inclusion: { in: DIFFICULTY_LEVELS }, allow_nil: true

  # Gym/musculacao exercises are only shown when they have a valid local GIF.
  # Other modalities (cardio, funcional, etc.) are always browseable.
  scope :browseable, -> {
    where(
      "(exercise_type != 'musculacao' AND equipment_type NOT IN ('gym','dumbbell','barbell','cable','machine'))" \
      " OR gif_url LIKE '/exercise-images/%'"
    )
  }

  # nil difficulty means accessible to all levels.
  scope :for_fitness_level, ->(level) {
    case level.to_s
    when "beginner"
      where(difficulty_level: ["beginner", nil])
    when "intermediate"
      where(difficulty_level: ["beginner", "intermediate", nil])
    else
      all
    end
  }
end

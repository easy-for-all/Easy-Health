class Exercise < ApplicationRecord
  MUSCLE_GROUPS    = %w[chest back shoulders biceps triceps legs core forearms calves glutes trapezius].freeze
  EXERCISE_TYPES   = %w[musculacao cardio natacao corrida funcional caminhada hiit timed].freeze
  EQUIPMENT_TYPES  = %w[bodyweight gym dumbbell barbell cable machine cardio].freeze
  GYM_EQUIPMENT    = %w[gym dumbbell barbell cable machine].freeze
  DIFFICULTY_LEVELS = %w[beginner intermediate advanced].freeze
  SAFETY_TAGS = %w[
    high_impact
    deep_knee_flexion
    heavy_spinal_loading
    high_spinal_flexion
    heavy_overhead_loading
    unstable_shoulder_loading
    high_wrist_extension
    high_neck_loading
    deep_hip_flexion
    aggressive_core_loading
    high_balance_demand
    high_fall_risk
    advanced_skill
  ].freeze

  has_many :workout_day_exercises, dependent: :destroy

  validates :name,             presence: true
  validates :exercise_type,    presence: true, inclusion: { in: EXERCISE_TYPES }
  validates :muscle_group,     inclusion: { in: MUSCLE_GROUPS }, allow_nil: true
  validates :equipment_type,   inclusion: { in: EQUIPMENT_TYPES }, allow_nil: true
  validates :difficulty_level, inclusion: { in: DIFFICULTY_LEVELS }, allow_nil: true
  validate :safety_tags_valid

  before_validation :normalize_safety_tags

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
      where(difficulty_level: [ "beginner", nil ])
    when "intermediate"
      where(difficulty_level: [ "beginner", "intermediate", nil ])
    else
      all
    end
  }

  private

  def normalize_safety_tags
    self.safety_tags = Array(safety_tags).filter_map { |tag| tag.to_s.strip.downcase.presence }.uniq
  end

  def safety_tags_valid
    invalid = Array(safety_tags) - SAFETY_TAGS
    errors.add(:safety_tags, "contém tags inválidas") if invalid.any?
  end
end

class Exercise < ApplicationRecord
  MUSCLE_GROUPS    = %w[chest back shoulders biceps triceps legs core forearms calves glutes trapezius].freeze
  EXERCISE_TYPES   = %w[musculacao cardio natacao corrida funcional caminhada hiit timed].freeze
  EQUIPMENT_TYPES  = %w[bodyweight gym dumbbell barbell cable machine cardio].freeze
  GYM_EQUIPMENT    = %w[gym dumbbell barbell cable machine].freeze
  DIFFICULTY_LEVELS = %w[beginner intermediate advanced].freeze
  TECHNICAL_COMPLEXITY_LEVELS = %w[low medium high].freeze
  RISK_LEVELS = %w[low medium high].freeze
  CALISTHENICS_SKILLS = %w[none basic advanced].freeze
  MOVEMENT_PATTERNS = %w[squat hinge push pull lunge carry rotation isolation locomotion].freeze
  OBJECTIVE_TAGS = %w[strength hypertrophy conditioning mobility health].freeze
  STYLE_TAGS = %w[traditional_strength calisthenics functional cardio mobility].freeze
  GIFDOTREINO_URL_PREFIX = "/exercise-images/gifdotreino/".freeze
  GIFDOTREINO_URL_PATTERN = "#{GIFDOTREINO_URL_PREFIX}%.gif".freeze
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
  belongs_to :regression_exercise, class_name: "Exercise", optional: true

  validates :name,                   presence: true
  validates :exercise_type,          presence: true, inclusion: { in: EXERCISE_TYPES }
  validates :muscle_group,           inclusion: { in: MUSCLE_GROUPS }, allow_nil: true
  validates :equipment_type,         inclusion: { in: EQUIPMENT_TYPES }, allow_nil: true
  validates :difficulty_level,       inclusion: { in: DIFFICULTY_LEVELS }, allow_nil: true
  validates :technical_complexity,   inclusion: { in: TECHNICAL_COMPLEXITY_LEVELS }, allow_nil: true
  validates :risk_level,             inclusion: { in: RISK_LEVELS }, allow_nil: true
  validates :calisthenics_skill,     inclusion: { in: CALISTHENICS_SKILLS }, allow_nil: true
  validates :movement_pattern,       inclusion: { in: MOVEMENT_PATTERNS }, allow_nil: true
  validate :safety_tags_valid
  validate :objective_tags_valid
  validate :style_tags_valid

  before_validation :normalize_safety_tags
  before_validation :normalize_objective_tags
  before_validation :normalize_style_tags

  scope :gifdotreino_source, -> { where("gif_url LIKE ?", GIFDOTREINO_URL_PATTERN) }
  scope :browseable, -> { gifdotreino_source }

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

  # Technical-complexity/risk/skill aware level filter — see
  # WorkoutIntelligence::TechnicalLevelPolicy. Used by the workout generator
  # instead of the weaker difficulty_level-based for_fitness_level above.
  scope :technically_safe_for, ->(level) {
    where(WorkoutIntelligence::TechnicalLevelPolicy.sql_conditions_for(level))
  }

  def self.gifdotreino_url?(url)
    value = url.to_s
    value.start_with?(GIFDOTREINO_URL_PREFIX) && value.downcase.end_with?(".gif")
  end

  def gifdotreino_source?
    self.class.gifdotreino_url?(gif_url)
  end

  private

  def normalize_safety_tags
    self.safety_tags = Array(safety_tags).filter_map { |tag| tag.to_s.strip.downcase.presence }.uniq
  end

  def normalize_objective_tags
    self.objective_tags = Array(objective_tags).filter_map { |tag| tag.to_s.strip.downcase.presence }.uniq
  end

  def normalize_style_tags
    self.style_tags = Array(style_tags).filter_map { |tag| tag.to_s.strip.downcase.presence }.uniq
  end

  def safety_tags_valid
    invalid = Array(safety_tags) - SAFETY_TAGS
    errors.add(:safety_tags, "contém tags inválidas") if invalid.any?
  end

  def objective_tags_valid
    invalid = Array(objective_tags) - OBJECTIVE_TAGS
    errors.add(:objective_tags, "contém tags inválidas") if invalid.any?
  end

  def style_tags_valid
    invalid = Array(style_tags) - STYLE_TAGS
    errors.add(:style_tags, "contém tags inválidas") if invalid.any?
  end
end

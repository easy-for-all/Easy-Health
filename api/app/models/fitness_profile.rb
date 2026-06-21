class FitnessProfile < ApplicationRecord
  PRIMARY_PERSONAS = %w[
    sedentary_beginner
    weight_loss_beginner
    hypertrophy_beginner
    hypertrophy_intermediate
    hypertrophy_advanced
    executive_low_time
    postpartum_return
    older_adult_mobility
    obese_weight_loss
    runner_performance
    rehabilitation_return
    high_frequency_athlete
    recomposition
    general_health
  ].freeze

  TRAINING_ARCHETYPES = %w[
    glute_focused
    lower_body_focused
    upper_body_focused
    aesthetic_hypertrophy
    strength_focused
    athletic_performance
    body_recomposition
    weight_loss
    cardio_focused
    functional_fitness
    mobility_focused
    health_and_longevity
    beginner_confidence_building
    postpartum_rebuild
    rehabilitation
    executive_short_sessions
    balanced_full_body
  ].freeze

  BEHAVIOR_PATTERNS = %w[
    unknown
    consistent_short_sessions
    inconsistent_usage
    skips_cardio
    skips_lower_body
    skips_upper_body
    avoids_unilateral_exercises
    prefers_machines
    prefers_free_weights
    prefers_cardio
    prefers_bodyweight
    abandons_long_workouts
    high_adherence
    low_adherence
    weekend_only
    morning_training
    evening_training
  ].freeze

  CURRENT_PHASES = %w[
    onboarding
    adaptation
    consistency_building
    progression
    deload
    recovery
    plateau_breaking
    maintenance
  ].freeze

  SCORE_FIELDS = %i[
    consistency_score
    adherence_score
    recovery_score
    mobility_score
    motivation_score
    risk_score
    preference_confidence_score
    behavior_confidence_score
  ].freeze

  belongs_to :user
  has_many :workout_strategies, dependent: :nullify
  has_many :coach_insights, dependent: :destroy

  validates :primary_persona, inclusion: { in: PRIMARY_PERSONAS }
  validates :secondary_persona, inclusion: { in: PRIMARY_PERSONAS }, allow_nil: true
  validates :training_archetype, inclusion: { in: TRAINING_ARCHETYPES }
  validates :secondary_training_archetype, inclusion: { in: TRAINING_ARCHETYPES }, allow_nil: true
  validates :behavior_pattern, inclusion: { in: BEHAVIOR_PATTERNS }
  validates :fitness_level, inclusion: { in: HealthProfile::FITNESS_LEVELS }
  validates :current_phase, inclusion: { in: CURRENT_PHASES }
  validates :classification_version, presence: true
  validates :training_maturity, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }

  SCORE_FIELDS.each do |field|
    validates field, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
  end
end

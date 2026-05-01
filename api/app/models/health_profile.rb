class HealthProfile < ApplicationRecord
  belongs_to :user

  FITNESS_LEVELS   = %w[beginner intermediate advanced].freeze
  GOALS            = %w[lose_weight gain_muscle maintain health].freeze
  ACTIVITY_TYPES   = %w[musculacao cardio natacao corrida funcional caminhada hiit].freeze

  validates :age,        presence: true, numericality: { only_integer: true, greater_than: 0, less_than: 120 }
  validates :weight_kg,  presence: true, numericality: { greater_than: 0 }
  validates :height_cm,  presence: true, numericality: { greater_than: 0 }
  validates :fitness_level, presence: true, inclusion: { in: FITNESS_LEVELS }
  validates :goal,          presence: true, inclusion: { in: GOALS }
  validates :training_days_per_week,
    numericality: { only_integer: true, in: 2..6 },
    allow_nil: true
  validate :activity_preferences_valid

  private

  def activity_preferences_valid
    return if activity_preferences.blank?
    invalid = activity_preferences - ACTIVITY_TYPES
    errors.add(:activity_preferences, "contains invalid values: #{invalid.join(', ')}") if invalid.any?
  end
end

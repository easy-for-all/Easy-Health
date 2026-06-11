class HealthProfile < ApplicationRecord
  belongs_to :user

  FITNESS_LEVELS      = %w[beginner intermediate advanced].freeze
  GOALS               = %w[lose_weight gain_muscle maintain health].freeze
  ACTIVITY_TYPES      = %w[musculacao cardio natacao corrida funcional caminhada hiit].freeze
  MODALITIES          = %w[musculacao cardio misto funcional ai_choice].freeze
  SPLIT_TYPES         = %w[ai_choice full_body upper_lower ab abc ppl custom].freeze
  CARDIO_TYPES        = %w[corrida caminhada bicicleta eliptico escada remo hiit natacao ai_choice].freeze
  CARDIO_FORMATS      = %w[continuo_leve continuo_moderado intervalado hiit progressivo recuperacao ai_choice].freeze
  TRAINING_LOCATIONS  = %w[gym home outdoor any].freeze
  GENDERS             = %w[male female not_informed].freeze

  validates :age,        presence: true, numericality: { only_integer: true, greater_than: 0, less_than: 120 }
  validates :weight_kg,  presence: true, numericality: { greater_than: 0 }
  validates :height_cm,  presence: true, numericality: { greater_than: 0 }
  validates :fitness_level, presence: true, inclusion: { in: FITNESS_LEVELS }
  validates :goal,          presence: true, inclusion: { in: GOALS }
  validates :training_days_per_week,
    numericality: { only_integer: true, in: 2..6 },
    allow_nil: true
  validates :modality,      inclusion: { in: MODALITIES },      allow_nil: true
  validates :split_type,    inclusion: { in: SPLIT_TYPES },     allow_nil: true
  validates :cardio_type,   inclusion: { in: CARDIO_TYPES },    allow_nil: true
  validates :cardio_format,      inclusion: { in: CARDIO_FORMATS },       allow_nil: true
  validates :training_location,  inclusion: { in: TRAINING_LOCATIONS },   allow_nil: true
  validates :gender,             inclusion: { in: GENDERS },              allow_nil: true
  validate :activity_preferences_valid

  before_validation :normalize_activity_preferences

  private

  # Sub-types of cardio that are valid for cardio_type but not for activity_preferences.
  # Normalize them to "cardio" so older clients and mobile don't break validation.
  CARDIO_SUBTYPES = %w[bicicleta eliptico escada remo].freeze

  def normalize_activity_preferences
    return if activity_preferences.blank?
    self.activity_preferences = activity_preferences.map do |pref|
      CARDIO_SUBTYPES.include?(pref) ? "cardio" : pref
    end
  end

  def activity_preferences_valid
    return if activity_preferences.blank?
    invalid = activity_preferences - ACTIVITY_TYPES
    errors.add(:activity_preferences, "contains invalid values: #{invalid.join(', ')}") if invalid.any?
  end
end

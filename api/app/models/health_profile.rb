class HealthProfile < ApplicationRecord
  belongs_to :user

  FITNESS_LEVELS      = %w[beginner intermediate advanced].freeze
  GOALS               = %w[
    lose_weight gain_muscle maintain health body_definition conditioning strength
    mobility safe_return health_longevity
  ].freeze
  ACTIVITY_TYPES      = %w[musculacao cardio natacao corrida funcional caminhada hiit].freeze
  MODALITIES          = %w[musculacao cardio misto funcional ai_choice].freeze
  SPLIT_TYPES         = %w[ai_choice full_body upper_lower ab abc ppl custom].freeze
  CARDIO_TYPES        = %w[corrida caminhada bicicleta eliptico escada remo hiit natacao ai_choice].freeze
  CARDIO_FORMATS      = %w[continuo_leve continuo_moderado intervalado hiit progressivo recuperacao ai_choice].freeze
  TRAINING_LOCATIONS  = %w[full_gym simple_gym home condo outdoor hotel_travel unknown].freeze
  GENDERS             = %w[male female not_informed].freeze
  BODY_FOCUS_OPTIONS   = %w[
    full_body glutes legs abs arms chest back shoulders mobility_posture conditioning_cardio
  ].freeze
  TRAINING_STYLES      = %w[
    traditional_strength short_sessions cardio functional calisthenics mobility mixed unknown
  ].freeze
  EQUIPMENT_OPTIONS    = %w[
    machine dumbbell barbell plates resistance_band treadmill stationary_bike rower jump_rope bodyweight none
  ].freeze
  SESSION_DURATIONS    = [ 15, 25, 35, 45, 60 ].freeze
  INTENSITY_PREFERENCES = %w[easy_start balanced intense progressive unknown].freeze
  TRAINING_CONTEXTS    = %w[none postpartum pregnant menstrual_cycle_impact prefer_not_to_say].freeze

  LEGACY_TRAINING_LOCATION_ALIASES = {
    "gym" => "full_gym",
    "any" => "unknown"
  }.freeze

  validates :age,        presence: true, numericality: { only_integer: true, greater_than: 0, less_than: 120 }
  validates :weight_kg,  presence: true, numericality: { greater_than: 0 }
  validates :height_cm,  presence: true, numericality: { greater_than: 0 }
  validates :fitness_level, presence: true, inclusion: { in: FITNESS_LEVELS }
  validates :goal,          presence: true, inclusion: { in: GOALS }
  validates :training_days_per_week,
    numericality: { only_integer: true, in: 1..6 },
    allow_nil: true
  validates :modality,      inclusion: { in: MODALITIES },      allow_nil: true
  validates :split_type,    inclusion: { in: SPLIT_TYPES },     allow_nil: true
  validates :cardio_type,   inclusion: { in: CARDIO_TYPES },    allow_nil: true
  validates :cardio_format,      inclusion: { in: CARDIO_FORMATS },       allow_nil: true
  validates :training_location,  inclusion: { in: TRAINING_LOCATIONS },   allow_nil: true
  validates :gender,             inclusion: { in: GENDERS },              allow_nil: true
  validates :session_duration_minutes, inclusion: { in: SESSION_DURATIONS }, allow_nil: true
  validates :intensity_preference, inclusion: { in: INTENSITY_PREFERENCES }, allow_nil: true
  validates :training_context, inclusion: { in: TRAINING_CONTEXTS }, allow_nil: true
  validate :activity_preferences_valid
  validate :preferred_body_focus_valid
  validate :preferred_training_styles_valid
  validate :available_equipment_valid

  before_validation :normalize_activity_preferences
  before_validation :normalize_preference_arrays
  before_validation :normalize_training_location

  after_commit :trigger_fitness_recalibration, on: :update, if: :training_preferences_changed?

  private

  PREFERENCE_FIELDS = %i[
    goal fitness_level training_days_per_week modality split_type training_location
    preferred_body_focus preferred_training_styles available_equipment limitations
    session_duration_minutes intensity_preference
  ].freeze

  def training_preferences_changed?
    PREFERENCE_FIELDS.any? { |f| saved_change_to_attribute?(f) }
  end

  def trigger_fitness_recalibration
    RecalibrateFitnessProfileJob.perform_later(user_id, source: "training_preferences_updated")
  end

  ACTIVITY_ALIASES = {
    # Portuguese variants
    "bicicleta"         => "cardio",
    "ciclismo"          => "cardio",
    "spinning"          => "cardio",
    "eliptico"          => "cardio",
    "escada"            => "cardio",
    "remo"              => "cardio",
    "musculação"        => "musculacao",
    "academia"          => "musculacao",
    "peso"              => "musculacao",
    "corrida"           => "corrida",
    "correr"            => "corrida",
    "caminhada"         => "caminhada",
    "andar"             => "caminhada",
    "natação"           => "natacao",
    "mobilidade"        => "funcional",
    "alongamento"       => "funcional",
    "funcional"         => "funcional",
    # English/canonical variants (from ExerciseIntelligenceService)
    "bike"              => "cardio",
    "cycling"           => "cardio",
    "running"           => "corrida",
    "walking"           => "caminhada",
    "strength"          => "musculacao",
    "strength_training" => "musculacao",
    "weights"           => "musculacao",
    "stretching"        => "funcional",
    "mobility"          => "funcional",
    "functional"        => "funcional",
    "hiit"              => "hiit",
    "swimming"          => "natacao",
    "cardio"            => "cardio"
  }.freeze

  def normalize_activity_preferences
    return if activity_preferences.blank?
    self.activity_preferences = activity_preferences.map do |pref|
      normalized = pref.to_s.downcase.strip
      ACTIVITY_ALIASES[normalized] || pref
    end.uniq
  end

  def normalize_preference_arrays
    self.preferred_body_focus = normalized_array(preferred_body_focus)
    self.preferred_training_styles = normalized_array(preferred_training_styles)
    self.available_equipment = normalized_array(available_equipment)
    self.avoided_exercise_ids = Array(avoided_exercise_ids).filter_map do |id|
      value = Integer(id, exception: false)
      value if value&.positive?
    end.uniq
  end

  def normalize_training_location
    value = training_location.to_s.strip.downcase
    self.training_location = LEGACY_TRAINING_LOCATION_ALIASES.fetch(value, value) if value.present?
  end

  def normalized_array(values)
    Array(values).filter_map { |value| value.to_s.strip.downcase.presence }.uniq
  end

  def activity_preferences_valid
    return if activity_preferences.blank?
    invalid = activity_preferences - ACTIVITY_TYPES
    if invalid.any?
      friendly = invalid.join(", ")
      errors.add(:activity_preferences, "Não entendemos a modalidade '#{friendly}'. Escolha entre as opções disponíveis.")
    end
  end

  def preferred_body_focus_valid
    invalid = Array(preferred_body_focus) - BODY_FOCUS_OPTIONS
    errors.add(:preferred_body_focus, "contém opções inválidas") if invalid.any?
    errors.add(:preferred_body_focus, "permite no máximo 3 opções") if Array(preferred_body_focus).size > 3
  end

  def preferred_training_styles_valid
    invalid = Array(preferred_training_styles) - TRAINING_STYLES
    errors.add(:preferred_training_styles, "contém opções inválidas") if invalid.any?
    errors.add(:preferred_training_styles, "permite apenas um estilo") if Array(preferred_training_styles).size > 1
  end

  def available_equipment_valid
    equipment = Array(available_equipment)
    invalid = equipment - EQUIPMENT_OPTIONS
    errors.add(:available_equipment, "contém opções inválidas") if invalid.any?
    errors.add(:available_equipment, "'none' não pode ser combinado com outros equipamentos") if equipment.include?("none") && equipment.size > 1
  end
end

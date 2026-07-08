module Ai
  class WorkoutChatReadiness
    MINIMUM_REQUIRED_FIELDS = %w[goal fitness_level training_days_per_week training_location].freeze

    def self.ready?(collected_profile)
      profile = collected_profile || {}
      MINIMUM_REQUIRED_FIELDS.all? { |field| profile[field].present? || profile[field.to_sym].present? }
    end
  end
end

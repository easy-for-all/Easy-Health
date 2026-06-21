module FitnessIntelligence
  FEATURE_FLAG = "USE_FITNESS_INTELLIGENCE_ENGINE".freeze

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch(FEATURE_FLAG, "false"))
  end

  def self.recalculate_safely(user:, source:)
    ProfileBuilder.new(user).call(source: source)
  rescue StandardError => e
    Rails.logger.error(
      "[FitnessIntelligence] Recalculation failed user_id=#{user.id} source=#{source}: #{e.class}: #{e.message}"
    )
    nil
  end
end

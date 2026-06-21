module FitnessIntelligence
  class ProfileBuilder
    VERSION = "v1".freeze
    HEALTH_DATA_STATUSES = %w[confirmed saved_advanced].freeze

    def initialize(user)
      @user = user
    end

    def call(source: "automatic")
      health_profile = @user.health_profile
      return nil unless health_profile

      fitness_profile = @user.fitness_profile || @user.build_fitness_profile
      created = fitness_profile.new_record?
      calculation = ScoreCalculator.new(user: @user, health_profile: health_profile).call

      fitness_profile.assign_attributes(
        profile_attributes(health_profile, calculation).merge(
          metadata: build_metadata(calculation, source),
          last_recalculated_at: Time.current
        )
      )
      fitness_profile.save!
      CoachEngine::ProfileAnalyzer.new(
        user: @user,
        fitness_profile: fitness_profile,
        health_profile: health_profile
      ).call(source: source)

      track_recalculation(fitness_profile, created, source)
      fitness_profile
    end

    private

    def profile_attributes(health_profile, calculation)
      {
        fitness_level: health_profile.fitness_level.presence || "beginner",
        current_goal: health_profile.goal,
        current_phase: current_phase(health_profile, calculation[:scores]),
        training_maturity: calculation[:training_maturity],
        preferred_body_focus: Array(health_profile.preferred_body_focus),
        preferred_exercises: @user.user_favorite_exercises.order(:exercise_id).pluck(:exercise_id),
        avoided_exercises: Array(health_profile.avoided_exercise_ids),
        preferred_training_styles: Array(health_profile.preferred_training_styles),
        available_equipment: available_equipment(health_profile),
        physical_limitations: limitations(health_profile),
        **calculation[:scores]
      }
    end

    def current_phase(health_profile, scores)
      return "onboarding" if @user.workout_sessions.empty?
      return "adaptation" if health_profile.fitness_level == "beginner" && @user.workout_sessions.count < 8
      return "recovery" if scores[:recovery_score] <= 3
      return "consistency_building" if scores[:consistency_score] < 5

      "progression"
    end

    def available_equipment(health_profile)
      declared = Array(health_profile.available_equipment)
      return declared if declared.any?

      {
        "full_gym" => %w[machine dumbbell barbell cable],
        "simple_gym" => %w[machine dumbbell barbell],
        "home" => %w[bodyweight],
        "condo" => %w[bodyweight],
        "outdoor" => %w[bodyweight cardio],
        "hotel_travel" => %w[bodyweight],
        "unknown" => []
      }.fetch(health_profile.training_location, [])
    end

    def limitations(health_profile)
      Array(health_profile.limitations).map { |limitation| limitation.to_s.strip }.reject(&:blank?)
    end

    def adult_bmi_caution?(health_profile)
      return false unless health_profile.age.to_i >= 18

      weight = health_profile.weight_kg.to_f
      height_meters = health_profile.height_cm.to_f / 100
      weight.positive? && height_meters.positive? && (weight / (height_meters**2)) >= 30
    end

    def build_metadata(calculation, source)
      confirmed_data_points = @user.health_data_points.where(status: HEALTH_DATA_STATUSES)
      {
        "version" => VERSION,
        "last_recalculation_source" => source.to_s,
        "score_breakdown" => calculation[:breakdown],
        "source_counts" => {
          "favorite_exercises" => @user.user_favorite_exercises.count,
          "training_preferences" => @user.user_training_preferences.count,
          "health_data_points" => confirmed_data_points.count,
          "health_metric_types" => confirmed_data_points.distinct.order(:field_name).pluck(:field_name),
          "body_photos" => @user.user_media.where(category: "body_photo").count,
          "exams" => @user.user_media.where(category: "exam").count,
          "active_workout_days" => @user.active_workout_plan&.workout_days&.count || 0
        },
        "safety_flags" => {
          "adult_bmi_caution" => adult_bmi_caution?(@user.health_profile)
        }
      }
    end

    def track_recalculation(fitness_profile, created, source)
      UserEventService.track(
        user: @user,
        event: created ? :fitness_profile_created : :fitness_profile_recalculated,
        metadata: {
          fitness_profile_id: fitness_profile.id,
          source: source.to_s,
          version: VERSION
        }
      )
    end
  end
end

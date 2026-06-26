module Api
  module V1
    class HealthProfilesController < BaseController
      def show
        profile = current_user.health_profile
        return render json: { error: "Profile not found" }, status: :not_found unless profile

        render json: profile_json(profile)
      end

      def create
        return update if current_user.health_profile

        profile = current_user.build_health_profile(normalized_profile_params)
        if save_profile_with_exercise_preferences(profile)
          FitnessIntelligence.recalculate_safely(user: current_user, source: "health_profile_created")
          WorkoutPlanGeneratorService.new(current_user).call
          render json: profile_json(profile), status: :created
        elsif !performed?
          render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        profile = current_user.health_profile || current_user.build_health_profile
        if save_profile_with_exercise_preferences(profile)
          FitnessIntelligence.recalculate_safely(user: current_user, source: "health_profile_updated")
          render json: profile_json(profile)
        elsif !performed?
          render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def profile_params
        params.permit(:age, :weight_kg, :height_cm, :fitness_level, :goal,
                      :training_days_per_week, :training_location, :gender, :session_duration_minutes,
                      :intensity_preference, :training_context,
                      activity_preferences: [], preferred_body_focus: [], preferred_training_styles: [],
                      available_equipment: [], avoided_exercise_ids: [], favorite_exercise_ids: [], limitations: [])
      end

      def normalized_profile_params
        p = profile_params.to_h
        p.delete("favorite_exercise_ids")
        if p["activity_preferences"].is_a?(Array)
          normalized = p["activity_preferences"].map { |v| ExerciseIntelligenceService.resolve_activity(v) }.compact
          p["activity_preferences"] = normalized.presence || p["activity_preferences"]
        end
        if p.key?("preferred_training_styles") && !p.key?("activity_preferences")
          p["activity_preferences"] = activities_for_styles(p["preferred_training_styles"])
        end
        p["avoided_exercise_ids"] = selected_exercise_ids(:avoided_exercise_ids) if p.key?("avoided_exercise_ids")
        p
      end

      def save_profile_with_exercise_preferences(profile)
        return false unless valid_exercise_preferences?

        HealthProfile.transaction do
          profile.assign_attributes(normalized_profile_params)
          profile.save!
          sync_favorite_exercises! if favorite_exercise_ids_provided?
        end
        true
      rescue ActiveRecord::RecordInvalid
        false
      end

      def valid_exercise_preferences?
        ids = selected_exercise_ids(:favorite_exercise_ids) + selected_exercise_ids(:avoided_exercise_ids)
        return true if ids.empty?
        return true if Exercise.where(id: ids).count == ids.uniq.size

        render json: { errors: [ "Um ou mais exercícios selecionados não existem." ] }, status: :unprocessable_entity
        false
      end

      def favorite_exercise_ids_provided?
        params.key?(:favorite_exercise_ids)
      end

      def selected_exercise_ids(key)
        Array(params[key]).filter_map do |id|
          value = Integer(id, exception: false)
          value if value&.positive?
        end.uniq
      end

      def sync_favorite_exercises!
        ids = selected_exercise_ids(:favorite_exercise_ids)
        current_user.user_favorite_exercises.where.not(exercise_id: ids).destroy_all
        ids.each { |exercise_id| current_user.user_favorite_exercises.find_or_create_by!(exercise_id: exercise_id) }
      end

      def activities_for_styles(styles)
        activities = Array(styles).flat_map do |style|
          {
            "traditional_strength" => [ "musculacao" ],
            "cardio" => [ "cardio" ],
            "functional" => [ "funcional" ],
            "calisthenics" => [ "funcional" ],
            "mobility" => [ "funcional" ],
            "mixed" => %w[musculacao cardio]
          }.fetch(style, [])
        end

        activities.presence || current_user.health_profile&.activity_preferences.presence || [ "musculacao" ]
      end

      def profile_json(profile)
        {
          id: profile.id,
          age: profile.age,
          weight_kg: profile.weight_kg,
          height_cm: profile.height_cm,
          fitness_level: profile.fitness_level,
          goal: profile.goal,
          activity_preferences: profile.activity_preferences || [],
          training_days_per_week: profile.training_days_per_week,
          training_location: profile.training_location,
          gender: profile.gender,
          preferred_body_focus: profile.preferred_body_focus || [],
          preferred_training_styles: profile.preferred_training_styles || [],
          available_equipment: profile.available_equipment || [],
          avoided_exercise_ids: profile.avoided_exercise_ids || [],
          session_duration_minutes: profile.session_duration_minutes,
          intensity_preference: profile.intensity_preference,
          training_context: profile.training_context,
          limitations: profile.limitations || [],
          favorite_exercise_ids: current_user.user_favorite_exercises.order(:exercise_id).pluck(:exercise_id),
          favorite_exercises: exercise_summaries(current_user.favorite_exercises),
          avoided_exercises: exercise_summaries(Exercise.where(id: profile.avoided_exercise_ids))
        }
      end

      def exercise_summaries(exercises)
        exercises.map { |exercise| { id: exercise.id, name: exercise.name, muscle_group: exercise.muscle_group } }
      end
    end
  end
end

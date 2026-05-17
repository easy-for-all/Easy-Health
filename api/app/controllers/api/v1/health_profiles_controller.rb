module Api
  module V1
    class HealthProfilesController < BaseController
      def show
        profile = current_user.health_profile
        return render json: { error: "Profile not found" }, status: :not_found unless profile

        render json: profile_json(profile)
      end

      def create
        if current_user.health_profile
          render_error("Profile already exists. Use PATCH to update.")
          return
        end

        profile = current_user.build_health_profile(profile_params)
        if profile.save
          WorkoutPlanGeneratorService.new(current_user).call
          render json: profile_json(profile), status: :created
        else
          render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        profile = current_user.health_profile || current_user.build_health_profile
        if profile.update(profile_params)
          render json: profile_json(profile)
        else
          render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def profile_params
        params.permit(:age, :weight_kg, :height_cm, :fitness_level, :goal,
                      :training_days_per_week, :training_location, activity_preferences: [])
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
          training_location: profile.training_location
        }
      end
    end
  end
end

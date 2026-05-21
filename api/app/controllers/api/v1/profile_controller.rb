module Api
  module V1
    class ProfileController < BaseController
      ALLOWED_DATA_TYPES = %w[workout_sessions workout_plans user_media health_data_points health_profile_optional].freeze

      def destroy_data
        types = Array(params[:data_types]).map(&:to_s) & ALLOWED_DATA_TYPES

        if types.empty?
          return render json: { error: "No valid data types specified" }, status: :unprocessable_entity
        end

        deleted = {}

        types.each do |type|
          case type
          when "workout_sessions"
            count = current_user.workout_sessions.count
            current_user.workout_sessions.destroy_all
            deleted[type] = count
          when "workout_plans"
            count = current_user.workout_plans.count
            current_user.workout_plans.destroy_all
            deleted[type] = count
          when "user_media"
            count = current_user.user_media.count
            current_user.user_media.each { |m| m.file.purge_later; m.destroy! }
            deleted[type] = count
          when "health_data_points"
            count = current_user.health_data_points.count
            current_user.health_data_points.destroy_all
            deleted[type] = count
          when "health_profile_optional"
            if current_user.health_profile.present?
              current_user.health_profile.update_columns(
                age: nil, weight_kg: nil, height_cm: nil,
                goal: nil, fitness_level: nil
              )
              deleted[type] = 1
            else
              deleted[type] = 0
            end
          end
        end

        render json: { message: "Data deleted successfully", deleted: deleted }, status: :ok
      rescue => e
        render json: { error: "Failed to delete data: #{e.message}" }, status: :unprocessable_entity
      end

      def update_avatar
        unless params[:avatar].present?
          return render json: { error: "No file uploaded" }, status: :unprocessable_entity
        end

        file = params[:avatar]
        unless file.content_type.start_with?("image/")
          return render json: { error: "Only image files are allowed" }, status: :unprocessable_entity
        end

        if file.size > 10.megabytes
          return render json: { error: "File too large (max 10MB)" }, status: :unprocessable_entity
        end

        current_user.avatar.attach(file)

        if current_user.avatar.attached?
          render json: { avatar_url: blob_path(current_user.avatar) }, status: :ok
        else
          render json: { error: "Upload failed" }, status: :unprocessable_entity
        end
      end
    end
  end
end

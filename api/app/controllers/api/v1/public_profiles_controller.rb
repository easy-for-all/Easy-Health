module Api
  module V1
    class PublicProfilesController < BaseController
      def show
        render json: {
          public_profile: serialize_public_profile_settings(current_user)
        }
      end

      def update
        pp = current_user.public_profile || current_user.create_public_profile!

        permitted = params.permit(
          :display_name, :avatar_visible, :city_visible, :country_visible,
          :public_bio, :show_workout_count, :show_streak, :show_points, :show_badges
        )

        pp.update!(permitted.to_h.compact)
        render json: { public_profile: serialize_public_profile_settings(current_user.reload) }
      rescue ActiveRecord::RecordInvalid => e
        render_error(e.record.errors.full_messages.to_sentence)
      end

      private

      def serialize_public_profile_settings(user)
        pp = user.public_profile
        {
          display_name: pp&.display_name,
          avatar_visible: pp&.avatar_visible || false,
          city_visible: pp&.city_visible || false,
          country_visible: pp&.country_visible || false,
          public_bio: pp&.public_bio,
          show_workout_count: pp&.show_workout_count.nil? ? true : pp.show_workout_count,
          show_streak: pp&.show_streak.nil? ? true : pp.show_streak,
          show_points: pp&.show_points || false,
          show_badges: pp&.show_badges || false,
          preview: serialize_public_profile(user)
        }
      end
    end
  end
end

module Api
  module V1
    class BadgesController < BaseController
      def index
        UserBadge.sync_for(current_user)
        earned_keys = current_user.user_badges.pluck(:badge_key).to_set

        badges = UserBadge::BADGE_DEFINITIONS.map do |defn|
          earned = earned_keys.include?(defn[:key])
          progress = badge_progress(defn[:key])
          {
            key:      defn[:key],
            icon:     defn[:icon],
            name:     defn[:name],
            desc:     defn[:desc],
            earned:   earned,
            progress: earned ? 100 : progress,
          }
        end

        render json: { badges: badges }
      end

      def user_badges
        user = User.joins(:public_profile)
          .where(users: { community_enabled: true, profile_visibility: %w[public_limited public] })
          .find_by(id: params[:user_id])
        return render_error("Perfil não encontrado", status: :not_found) unless user

        earned = user.user_badges.pluck(:badge_key).to_set
        badges = UserBadge::BADGE_DEFINITIONS
          .select { |d| earned.include?(d[:key]) }
          .map { |d| { key: d[:key], icon: d[:icon], name: d[:name] } }

        render json: { badges: badges }
      end

      private

      def badge_progress(key)
        case key
        when "streak_3"  then [(UserBadge.current_streak(current_user) / 3.0 * 100).to_i, 99].min
        when "streak_7"  then [(UserBadge.current_streak(current_user) / 7.0 * 100).to_i, 99].min
        when "streak_30" then [(UserBadge.current_streak(current_user) / 30.0 * 100).to_i, 99].min
        when "workouts_10"  then [(current_user.workout_sessions.count / 10.0 * 100).to_i, 99].min
        when "workouts_50"  then [(current_user.workout_sessions.count / 50.0 * 100).to_i, 99].min
        when "workouts_100" then [(current_user.workout_sessions.count / 100.0 * 100).to_i, 99].min
        else 0
        end
      end
    end
  end
end

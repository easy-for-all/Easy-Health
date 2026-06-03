module Api
  module V1
    class UsersController < BaseController
      SEARCH_RATE_LIMIT = 30

      def index
        query = params[:q].to_s.strip
        return render_error("Query must have at least 2 characters") if query.length < 2

        users = User
          .where(profile_visibility: %w[public public_limited])
          .where("name ILIKE ?", "%#{User.sanitize_sql_like(query)}%")
          .where.not(id: current_user.id)
          .includes(:public_profile)
          .limit(20)

        render json: { users: users.map { |u| serialize_public_profile(u) } }
      end

      def show
        user = User.where(profile_visibility: %w[public public_limited])
                   .includes(:public_profile)
                   .find(params[:id])

        render json: { user: serialize_public_profile(user) }
      rescue ActiveRecord::RecordNotFound
        render_error("User not found", status: :not_found)
      end
    end
  end
end

module Api
  module V1
    class SharedWorkoutsController < BaseController
      skip_before_action :authenticate_user!, only: [:show_by_token]

      def index
        workouts = current_user.shared_workouts.order(created_at: :desc)
        render json: { shared_workouts: workouts.map { |sw| serialize_shared(sw) } }
      end

      def create
        workout_day_id = params.require(:workout_day_id)
        options = {
          visibility: params[:visibility] || "private_link",
          include_weights: ActiveModel::Type::Boolean.new.cast(params[:include_weights]),
          include_notes: ActiveModel::Type::Boolean.new.cast(params[:include_notes]),
          expires_in_days: params[:expires_in_days],
          title: params[:title]
        }

        shared = WorkoutShareService.new(current_user, workout_day_id, options).call
        render json: { shared_workout: serialize_shared(shared) }, status: :created
      rescue ActiveRecord::RecordNotFound
        render_error("Workout day not found", status: :not_found)
      rescue ActiveRecord::RecordInvalid => e
        render_error(e.record.errors.full_messages.to_sentence)
      end

      def destroy
        shared = current_user.shared_workouts.find(params[:id])
        shared.destroy!
        render json: { message: "Sharing revoked" }
      rescue ActiveRecord::RecordNotFound
        render_error("Shared workout not found", status: :not_found)
      end

      def show_by_token
        shared = SharedWorkout.find_by(token: params[:token])

        if shared.nil? || shared.expired?
          return render_error("Shared workout not found or expired", status: :not_found)
        end

        shared.increment!(:view_count)
        render json: { shared_workout: serialize_shared_public(shared) }
      end

      private

      def serialize_shared(sw)
        {
          id: sw.id,
          token: sw.token,
          title: sw.title,
          visibility: sw.visibility,
          include_weights: sw.include_weights,
          include_notes: sw.include_notes,
          expires_at: sw.expires_at,
          view_count: sw.view_count,
          exercise_count: sw.snapshot.dig("exercise_count") || 0,
          share_url: "/s/#{sw.token}",
          created_at: sw.created_at
        }
      end

      def serialize_shared_public(sw)
        snapshot = sw.snapshot
        exercises = snapshot["exercises"] || []

        # Strip weights if not permitted
        exercises = exercises.map { |e| e.except("weight_kg") } unless sw.include_weights

        {
          id: sw.id,
          title: sw.title,
          shared_by: sw.owner.public_profile&.display_name || sw.owner.name,
          visibility: sw.visibility,
          snapshot: snapshot.merge("exercises" => exercises),
          view_count: sw.view_count,
          created_at: sw.created_at
        }
      end
    end
  end
end

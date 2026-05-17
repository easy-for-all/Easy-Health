module Api
  module V1
    class HealthDataPointsController < BaseController
      def index
        points = current_user.health_data_points.pending.order(created_at: :desc)
        render json: points.map { |p| serialize(p) }
      end

      def update
        point = current_user.health_data_points.find(params[:id])
        action = params[:action_type].to_s

        case action
        when "confirm"
          apply_to_profile(point)
          point.update!(status: "confirmed")
        when "save_advanced"
          point.update!(status: "saved_advanced")
        when "ignore"
          point.update!(status: "ignored")
        else
          return render json: { error: "Invalid action. Use confirm, save_advanced, or ignore." },
                        status: :unprocessable_entity
        end

        render json: serialize(point)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      private

      PROFILE_FIELD_MAP = {
        "weight_kg"    => :weight_kg,
        "height_cm"    => :height_cm,
        "body_fat_pct" => :body_fat_percentage,
      }.freeze

      def apply_to_profile(point)
        profile_field = PROFILE_FIELD_MAP[point.field_name]
        return unless profile_field && point.value.present?

        profile = current_user.health_profile || current_user.build_health_profile
        profile.update!(profile_field => point.value)
      end

      def serialize(point)
        {
          id:           point.id,
          field_name:   point.field_name,
          value:        point.value,
          unit:         point.unit,
          source_type:  point.source_type,
          status:       point.status,
          confidence:   point.confidence,
          ai_notes:     point.ai_notes,
          raw_text:     point.raw_text,
          collected_at: point.collected_at,
          user_media_id: point.user_media_id,
        }
      end
    end
  end
end

module Api
  module V1
    class CoachInsightsController < BaseController
      INSIGHTS_LIMIT = 10

      def index
        insights = current_user.coach_insights
          .unread
          .recent
          .limit(INSIGHTS_LIMIT)

        render json: insights.map { |i| serialize_insight(i) }
      end

      def read
        insight = current_user.coach_insights.find(params[:id])
        insight.mark_read!
        render json: { id: insight.id, read_at: insight.read_at }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      private

      def serialize_insight(insight)
        {
          id:           insight.id,
          insight_type: insight.insight_type,
          title:        insight.title,
          message:      insight.message,
          severity:     insight.severity,
          source:       insight.source,
          read_at:      insight.read_at,
          created_at:   insight.created_at
        }
      end
    end
  end
end

module Api
  module V1
    module Admin
      # Product analytics endpoints for the Admin dashboard, by domain. Each
      # action returns MetricResult-shaped data (numerator/denominator/status/
      # cohort_maturity), never a bare percentage.
      class AnalyticsController < BaseController
        before_action :require_admin!

        # GET /api/v1/admin/analytics/platform_comparison
        # "Impacto do app Android" (Fase 15) — Android vs Web vs PWA cohorts.
        def platform_comparison
          render json: ::Analytics::PlatformComparison.new.call
        end
      end
    end
  end
end

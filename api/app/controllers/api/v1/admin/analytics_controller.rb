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

        # GET /api/v1/admin/analytics/android_installations
        # "APP ANDROID" — the real installed base from app_installations,
        # separating installations / devices / users / sessions, and splitting
        # historical / current tracking (build >= reconciliation threshold) /
        # legacy so the tracking health rate is never diluted by old builds.
        def android_installations
          render json: ::Analytics::AndroidInstallations.new.call
        rescue StandardError => e
          # Only real failures are logged — a normal dashboard load stays silent.
          Rails.logger.error(
            "[Admin::Analytics#android_installations] #{e.class}: #{e.message}"
          )
          render json: { error: "Métricas de instalação indisponíveis no momento." },
                 status: :service_unavailable
        end
      end
    end
  end
end

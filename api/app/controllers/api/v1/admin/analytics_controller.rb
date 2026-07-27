module Api
  module V1
    module Admin
      # Product analytics endpoints for the Admin dashboard, by domain. Each
      # action returns MetricResult-shaped data (numerator/denominator/status/
      # cohort_maturity), never a bare percentage.
      class AnalyticsController < BaseController
        before_action :require_admin!

        EVENT_DELIVERY_PERIODS = {
          "24h" => 24.hours,
          "7d" => 7.days,
          "30d" => 30.days
        }.freeze

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

        # GET /api/v1/admin/analytics/event_deliveries
        def event_deliveries
          page = [ params[:page].to_i, 1 ].max
          per = params[:per].presence&.to_i&.clamp(1, 100) || 25
          scope = filtered_event_delivery_scope
          rows = scope.order(created_at: :desc).limit(per).offset((page - 1) * per)

          render json: {
            summary: event_delivery_summary(scope),
            deliveries: rows.map { |event| event_delivery_row(event) },
            total: scope.count,
            page: page,
            per: per
          }
        end

        # GET /api/v1/admin/analytics/event_deliveries/:id
        def event_delivery
          event = UserEvent.includes(:user).find(params[:id])
          render json: { delivery: event_delivery_detail(event) }
        end

        private

        def filtered_event_delivery_scope
          scope = UserEvent.includes(:user).where(created_at: event_delivery_period_range)
          scope = scope.where("user_events.event_name ILIKE ?", "%#{sql_like(params[:event_name])}%") if params[:event_name].present?
          scope = filter_event_delivery_user(scope)
          scope = scope.where("user_events.make_delivery_channels ? :channel", channel: params[:channel].to_s) if params[:channel].present?
          scope = scope.where(make_destination: params[:destination]) if params[:destination].present?
          scope = scope.where(make_delivery_status: params[:delivery_status]) if params[:delivery_status].present?
          scope = scope.where(make_last_http_status: params[:http_status].to_i) if params[:http_status].present?
          scope = scope.where(make_processing_status: params[:make_status]) if params[:make_status].present?
          scope
        end

        def event_delivery_period_range
          return parsed_time(params[:from])..parsed_time(params[:to]) if params[:from].present? && params[:to].present?

          period = EVENT_DELIVERY_PERIODS.fetch(params[:period].presence || "24h", EVENT_DELIVERY_PERIODS["24h"])
          period.ago..Time.current
        end

        def filter_event_delivery_user(scope)
          query = params[:user].to_s.strip
          return scope if query.blank?

          if query.match?(/\A\d+\z/)
            scope.where(user_id: query.to_i)
          else
            pattern = "%#{sql_like(query)}%"
            scope.joins(:user).where("users.email ILIKE :pattern OR users.name ILIKE :pattern", pattern: pattern)
          end
        end

        def event_delivery_summary(scope)
          {
            events_generated: scope.count,
            accepted_by_make: scope.where(make_delivery_status: "accepted_by_make").count,
            with_error: scope.where(make_delivery_status: UserEvent::ERROR_DELIVERY_STATUSES).count,
            pending_or_retry: scope.where(make_delivery_status: UserEvent::ACTIVE_DELIVERY_STATUSES).count
          }
        end

        def event_delivery_row(event)
          {
            id: event.id,
            event_name: event.event_name,
            occurred_at: event.occurred_at&.iso8601,
            created_at: event.created_at&.iso8601,
            user: event_delivery_user(event.user),
            channels: event_delivery_channels(event),
            destination: event_delivery_destination(event),
            delivery_status: event.make_delivery_status,
            attempt_count: event.make_attempts_count,
            http_status: event.make_last_http_status,
            make_status: event.make_processing_status.presence || "unknown"
          }
        end

        def event_delivery_detail(event)
          event_delivery_row(event).merge(
            source: event.source,
            first_attempt_at: event.make_first_attempt_at&.iso8601,
            last_attempt_at: event.make_last_attempt_at&.iso8601,
            next_retry_at: event.make_next_retry_at&.iso8601,
            delivered_to_provider_at: event.make_delivered_to_provider_at&.iso8601,
            response_body: event.make_last_response_body,
            error_class: event.make_last_error_class,
            error_message: event.make_last_error_message.presence || event.make_last_error,
            delivery_duration_ms: event.make_delivery_duration_ms,
            idempotency_key: event.idempotency_key,
            make_execution_id: event.make_execution_id,
            make_callback_at: event.make_callback_at&.iso8601,
            make_processing_message: event.make_processing_message,
            payload: event.payload_json || {},
            metadata: event.metadata || {}
          )
        end

        def event_delivery_user(user)
          return nil unless user

          {
            id: user.id,
            admin_display_id: "EH-#{user.id.to_s.rjust(6, '0')}",
            name: user.name,
            display_name: user.name.presence || "Usuário EH-#{user.id.to_s.rjust(6, '0')}",
            email: user.email
          }
        end

        def event_delivery_channels(event)
          channels = event.make_delivery_channels_list
          channels = Array(event.payload_json&.dig("delivery", "channels")).map(&:to_s) if channels.empty?
          channels = CommunicationEvents.channels_for(event.event_name) if channels.empty?
          channels
        rescue CommunicationEvents::ConfigError
          []
        end

        def event_delivery_destination(event)
          return event.make_destination if event.make_destination.present?

          channels = event_delivery_channels(event)
          communication_type = CommunicationEvents.communication_type_for(event.event_name).presence
          return communication_type if channels.empty?

          ([ channels.sort.join("-"), communication_type ].compact.join("-")).presence
        rescue CommunicationEvents::ConfigError
          nil
        end

        def sql_like(value)
          ActiveRecord::Base.sanitize_sql_like(value.to_s)
        end

        def parsed_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          Time.current
        end
      end
    end
  end
end

module Api
  module V1
    module Admin
      # Admin-only observability panel API.
      #
      # NOTE ON CONSTANT RESOLUTION: every reference to the Observability
      # namespace is root-qualified (::Observability::...). Api::V1::Analytics
      # already shadows ::Analytics in this tree (see admin/analytics_controller.rb),
      # and the day someone adds an Api::V1::Observability every unqualified
      # reference here would silently resolve to the wrong constant.
      #
      # Authorization is enforced server-side on every action. The frontend gate
      # is a redirect, not a control — and this payload is considerably more
      # sensitive than the existing dashboards.
      class ObservabilityController < BaseController
        before_action :require_admin!

        CACHE_KEY = "observability:dashboard".freeze
        MAX_PER_PAGE = 100

        def show
          payload = cached_dashboard
          response.headers["Cache-Control"] = "private, max-age=30"
          render json: payload
        rescue ActiveRecord::StatementInvalid => e
          Rails.logger.error("[Admin::Observability#show] #{e.class}: #{e.message}")
          Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
          render json: { error: "Painel de observabilidade indisponível no momento." }, status: :service_unavailable
        end

        def incidents
          scope = ObservabilityIncident.all
          scope = scope.where(status: status_filter) if status_filter.present?
          scope = scope.where(severity: params[:severity]) if params[:severity].present?
          scope = scope.where(source: params[:source]) if params[:source].present?

          total = scope.count
          records = scope.recent_first.offset((page - 1) * per_page).limit(per_page)

          render json: {
            incidents: records.map(&:as_observability_json),
            pagination: { page: page, per_page: per_page, total: total }
          }
        end

        def acknowledge
          incident = ObservabilityIncident.find(params[:id])
          ::Observability::IncidentManager.acknowledge!(incident, acknowledged_by: actor_ref)
          bust_cache
          render json: incident.reload.as_observability_json
        end

        def resolve
          incident = ObservabilityIncident.find(params[:id])
          ::Observability::IncidentManager.resolve!(incident, resolved_by: actor_ref)
          bust_cache
          render json: incident.reload.as_observability_json
        end

        # Investigation timeline for one user or one installation.
        #
        # PRIVACY: returns event names and timestamps only. No email, no name,
        # no token, no raw properties — the properties blob can contain
        # arbitrary client-supplied keys, so it is never echoed wholesale.
        def timeline
          if params[:user_id].blank? && params[:installation_id].blank?
            render json: { error: "Informe user_id ou installation_id." }, status: :bad_request
            return
          end

          user_id, installation = resolve_subject
          # An installation id that resolves to nothing is a legitimate answer
          # ("we have never seen this device"), not a bad request — that is
          # often exactly what the investigator is trying to confirm.

          render json: {
            subject: {
              user_ref: user_id ? "u_#{user_id}" : nil,
              installation_found: !installation.nil?,
              installation_linked: !installation&.user_id.nil?,
              platform: installation&.platform,
              app_version: installation&.app_version,
              app_build: installation&.app_build,
              build_group: installation && ::Observability::BuildGroup.for(installation.app_build),
              first_seen_at: installation&.first_seen_at,
              last_seen_at: installation&.last_seen_at,
              last_authenticated_at: installation&.last_authenticated_at
            },
            events: timeline_events(user_id, installation)
          }
        end

        private

        def cached_dashboard
          bust_cache if ActiveModel::Type::Boolean.new.cast(params[:refresh])

          Rails.cache.fetch(cache_key, expires_in: ::Observability::Config.dashboard_cache_seconds.seconds) do
            ::Observability::Dashboard.new(range: params[:range]).call
          end
        end

        def cache_key
          "#{CACHE_KEY}:#{params[:range].presence || '24h'}"
        end

        def bust_cache
          %w[24h 7d 30d].each { |range| Rails.cache.delete("#{CACHE_KEY}:#{range}") }
        end

        # Auditable without being personal: the admin's internal id, never their
        # email or name.
        def actor_ref
          "admin:#{current_user.id}"
        end

        def status_filter
          case params[:status].to_s
          when "open" then ObservabilityIncident::ACTIVE_STATUSES
          when "resolved" then ObservabilityIncident::STATUS_RESOLVED
          when "acknowledged" then ObservabilityIncident::STATUS_ACKNOWLEDGED
          end
        end

        def page
          [ params[:page].to_i, 1 ].max
        end

        def per_page
          requested = params[:per_page].to_i
          requested = 25 if requested <= 0
          [ requested, MAX_PER_PAGE ].min
        end

        def resolve_subject
          installation_id = params[:installation_id].to_s.strip.presence
          installation = installation_id && AppInstallation.find_by(installation_id: installation_id)

          user_id = params[:user_id].presence&.to_i
          user_id ||= installation&.user_id
          user_id = nil unless user_id&.positive?

          [ user_id, installation ]
        end

        TIMELINE_EVENTS = %w[
          app_first_open app_opened session_started web_session_started
          landing_page_viewed native_entry_viewed auth_screen_viewed signup_selected login_selected
          auth_provider_clicked
          signup_started login_started login_failed
          social_login_started social_login_failed social_login_completed
          auth_client_error auth_api_error
          google_auth_started google_auth_succeeded google_auth_failed
          email_auth_started email_auth_succeeded email_auth_failed
          android_registration_started android_registration_succeeded android_registration_failed
          installation_link_succeeded installation_link_failed
          signup_completed login_completed
          workout_created workout_started workout_completed
        ].freeze

        TIMELINE_LIMIT = 200

        # The anonymous half of the journey is keyed on properties->>'installation_id'
        # (written by analytics/server.ts and by Observability::Context), NOT on
        # session_id. Matching session_id against an installation_id compared two
        # unrelated uuids, so this branch silently returned nothing and every
        # pre-signup investigation had to be done by hand, by timestamp.
        INSTALLATION_PROPERTY_SQL = "product_analytics_events.properties->>'installation_id' = ?".freeze

        def timeline_events(user_id, installation)
          # Nothing to search on: an installation id we have never seen, with no
          # user id to fall back to.
          return [] if user_id.nil? && installation.nil?

          scope = ProductAnalyticsEvent.where(event_name: TIMELINE_EVENTS)

          scope =
            if user_id && installation
              # An installation can precede the account, so both keys are needed
              # to see the pre-signup part of the journey.
              scope.where(user_id: user_id).or(
                ProductAnalyticsEvent.where(event_name: TIMELINE_EVENTS)
                                     .where(INSTALLATION_PROPERTY_SQL, installation.installation_id)
              )
            elsif user_id
              scope.where(user_id: user_id)
            else
              scope.where(INSTALLATION_PROPERTY_SQL, installation.installation_id)
            end

          scope.order(occurred_at: :desc).limit(TIMELINE_LIMIT).map do |event|
            {
              event_name: event.event_name,
              occurred_at: event.occurred_at,
              platform: event.platform,
              app_version: event.app_version,
              app_build: event.build_number,
              # Explicit allow-list. `properties` is client-influenced and must
              # never be echoed whole into an admin response.
              result: safe_property(event, "result"),
              error_code: safe_property(event, "error_code"),
              # What separates a deliberate exit from a defect. Without it the
              # panel had to paint every social_login_failed red, including the
              # ones where the user simply changed their mind.
              failure_category: safe_property(event, "failure_category"),
              auth_attempt_id: safe_property(event, "auth_attempt_id"),
              auth_flow: safe_property(event, "auth_flow"),
              link_result: safe_property(event, "link_result"),
              auth_screen: safe_property(event, "auth_screen"),
              intent: safe_property(event, "intent"),
              terms_accepted: safe_property(event, "terms_accepted"),
              stage: safe_property(event, "stage"),
              http_status: safe_property(event, "http_status"),
              provider: safe_property(event, "provider")
            }.compact
          end
        end

        def safe_property(event, key)
          value = event.properties.is_a?(Hash) ? event.properties[key] : nil
          return nil if value.nil?

          value.to_s[0, 64]
        end
      end
    end
  end
end

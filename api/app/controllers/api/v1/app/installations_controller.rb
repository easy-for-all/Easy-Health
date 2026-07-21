module Api
  module V1
    module App
      # App installation register/refresh.
      #
      # Auth is OPTIONAL (inherits from ApplicationController, not BaseController):
      # an installation exists before login. When a Devise session cookie is
      # present, current_user is associated server-side — the client never asserts
      # its own user_id. Rate-limited by Rack::Attack (app-installations/ip).
      class InstallationsController < ApplicationController
        MAX_BODY_BYTES = 4_096

        # POST /api/v1/app/installations/register
        def register
          upsert(params[:installation_id])
        end

        # PATCH /api/v1/app/installations/:installation_id
        def update
          upsert(params[:installation_id])
        end

        private

        def upsert(installation_id)
          if installation_id.to_s.strip.blank?
            render json: { error: "installation_id required" }, status: :bad_request
            return
          end

          if oversized_body?
            render json: { error: "payload too large" }, status: :content_too_large
            return
          end

          result = AppInstallations::Register.new(
            user: current_user,
            installation_id: installation_id,
            attributes: installation_params
          ).call

          if result.ok
            render json: { installation_id: installation_id.to_s.strip, created: result.created },
                   status: result.created ? :created : :ok
          else
            # Disabled by flag or a swallowed failure — never break the client.
            head :accepted
          end
        rescue StandardError => e
          Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
          Rails.logger.error("[installations] endpoint error: #{e.class}: #{e.message}")
          head :accepted
        end

        def oversized_body?
          request.content_length.to_i > MAX_BODY_BYTES
        end

        def installation_params
          params.permit(*AppInstallations::Register::ALLOWED_ATTRS).to_h.symbolize_keys
        end
      end
    end
  end
end

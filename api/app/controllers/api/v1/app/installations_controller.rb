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
        MAX_INSTALLATION_ID_BYTES = 128

        # POST /api/v1/app/installations/register
        def register
          # session_started is a client control flag (only app boot sends it true);
          # never inferred from the HTTP verb — a post-login re-register omits it.
          upsert(params[:installation_id], session_started: params[:session_started])
        end

        # PATCH /api/v1/app/installations/:installation_id
        def update
          # A refresh is never a session start.
          upsert(params[:installation_id], session_started: false)
        end

        private

        def upsert(installation_id, session_started:)
          normalized_id = installation_id.to_s.strip

          # Malformed request: the resource key itself is missing.
          if normalized_id.blank?
            render json: { error: "installation_id required" }, status: :bad_request
            return
          end

          # Present-but-invalid client input is rejected explicitly (422) — observable,
          # never a silent success.
          if normalized_id.bytesize > MAX_INSTALLATION_ID_BYTES
            render json: { error: "installation_id too long" }, status: :unprocessable_entity
            return
          end

          if invalid_platform?
            render json: { error: "invalid platform" }, status: :unprocessable_entity
            return
          end

          if oversized_body?
            render json: { error: "payload too large" }, status: :content_too_large
            return
          end

          result = AppInstallations::Register.new(
            user: current_user,
            installation_id: installation_id,
            attributes: installation_params,
            session_started: session_started
          ).call

          if result.ok
            render json: { installation_id: normalized_id, created: result.created },
                   status: result.created ? :created : :ok
          else
            # Disabled by flag or a swallowed internal failure (already sent to
            # Sentry by the service) — stay non-blocking, never break the client.
            head :accepted
          end
        rescue StandardError => e
          # Unexpected internal error: observable in Sentry/logs, non-blocking to the
          # client (tracking must never break app boot/login), and never disguised as success.
          Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
          Rails.logger.error("[installations] endpoint error: #{e.class}: #{e.message}")
          head :accepted
        end

        # Reject a platform the client explicitly sent that is outside the allowlist,
        # rather than silently coercing it to "unknown".
        def invalid_platform?
          raw = params[:platform]
          raw.present? && !AppInstallation::PLATFORMS.include?(raw.to_s)
        end

        def oversized_body?
          request.content_length.to_i > MAX_BODY_BYTES
        end

        def installation_params
          permitted = AppInstallations::Register::ALLOWED_ATTRS +
                      AppInstallations::Register::REFERRER_ATTRS
          params.permit(*permitted).to_h.symbolize_keys
        end
      end
    end
  end
end

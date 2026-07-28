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

        # Response contract. The client decides whether the installation really
        # exists on the backend from `status`/`registered` in the body, never
        # from "it was a 2xx": an acceptance is not a registration.
        #
        #   registered        200/201 — the row was created or updated
        #   deferred          202     — nothing was written, retry later
        #   disabled          202     — kill-switch off, do NOT retry
        #   validation_failed 422     — the payload is the problem, do NOT retry
        #   invalid_request   400     — malformed request
        #
        # Link statuses are echoed for diagnostics only; nothing else about the
        # installation or its user is exposed.
        LINK_STATUSES = %w[linked already_linked conflict].freeze

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
            render_rejected("invalid_request", "installation_id required", :bad_request)
            return
          end

          # Present-but-invalid client input is rejected explicitly (422) — observable,
          # never a silent success.
          if normalized_id.bytesize > MAX_INSTALLATION_ID_BYTES
            render_rejected("validation_failed", "installation_id too long")
            return
          end

          if invalid_platform?
            render_rejected("validation_failed", "invalid platform")
            return
          end

          if oversized_body?
            render_rejected("validation_failed", "payload too large", :content_too_large)
            return
          end

          result = AppInstallations::Register.new(
            user: current_user,
            installation_id: installation_id,
            attributes: installation_params,
            session_started: session_started
          ).call

          render_result(result, normalized_id)
        rescue StandardError => e
          # Unexpected internal error: observable in Sentry/logs, non-blocking to the
          # client (tracking must never break app boot/login), and never disguised as success.
          Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
          Rails.logger.error("[installations] endpoint error: #{e.class}: #{e.message}")
          render_deferred("internal_error")
        end

        def render_result(result, normalized_id)
          case result.status
          when :registered
            # The only branch that claims a registration: the row is persisted.
            render json: {
              status: "registered",
              registered: true,
              installation_id: normalized_id,
              created: result.created,
              link_status: link_status_for(result.link_result)
            }, status: result.created ? :created : :ok
          when :disabled
            # Nothing was written and nothing ever will be while the flag is off.
            # Saying "registered" here is exactly the lie this contract removes.
            render json: { status: "disabled", registered: false, retryable: false }, status: :accepted
          when :validation_failed
            render_rejected("validation_failed", "installation rejected")
          else
            # Transient/internal: accepted so tracking never blocks the app, but
            # explicitly not registered, so the client retries on a later cycle.
            render_deferred("register_unavailable")
          end
        end

        def render_deferred(reason)
          render json: { status: "deferred", registered: false, retryable: true, reason: reason },
                 status: :accepted
        end

        # A client-side problem: repeating the same payload would fail identically.
        def render_rejected(status_name, message, http_status = :unprocessable_entity)
          render json: { status: status_name, registered: false, retryable: false, error: message },
                 status: http_status
        end

        def link_status_for(link_result)
          status = link_result&.status.to_s
          LINK_STATUSES.include?(status) ? status : nil
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

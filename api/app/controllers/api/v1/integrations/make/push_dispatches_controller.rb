module Api
  module V1
    module Integrations
      module Make
        # Internal endpoint the Make orchestrator calls to request a push.
        # Auth is a dedicated Bearer token (separate from the inbound webhook
        # secret), compared in constant time, with CURRENT/PREVIOUS support for
        # zero-downtime rotation. All business logic lives in the service.
        class PushDispatchesController < ActionController::API
          MAX_BODY_BYTES = 8_192
          # A device token must NEVER be supplied by Make. Strong params would
          # silently drop these, so we inspect the raw body and reject loudly —
          # a token here signals a misconfigured scenario.
          FORBIDDEN_FIELDS = %w[token device_token fcm_token tokens].freeze

          before_action :require_https_in_production
          before_action :verify_bearer_token
          before_action :enforce_body_size
          before_action :reject_forbidden_fields

          def create
            response = ::Make::PushDispatchRequest.call(
              params: dispatch_params,
              test_token_valid: test_bypass_token_valid?
            )
            render json: response.body, status: response.http_status
          rescue => e
            Rails.logger.error("[Make::PushDispatches] #{e.class}: #{e.message}")
            Rails.logger.error(e.backtrace.first(5).join("\n"))
            head :internal_server_error
          end

          private

          def dispatch_params
            params.permit(
              :event_id, :user_id, :notification_type, :campaign_key,
              :title, :body, :route, :correlation_id,
              data: {}
            )
          end

          def verify_bearer_token
            provided = bearer_token
            expected = allowed_dispatch_tokens

            if expected.empty?
              Rails.logger.error("[Make::PushDispatches] MAKE_PUSH_DISPATCH_TOKEN not configured")
              head :internal_server_error and return
            end

            authorized = provided.present? && expected.any? do |token|
              ActiveSupport::SecurityUtils.secure_compare(token, provided)
            end

            unless authorized
              Rails.logger.warn("[Make::PushDispatches] unauthorized dispatch attempt from #{request.remote_ip}")
              head :unauthorized
            end
          end

          def bearer_token
            header = request.headers["Authorization"].to_s
            header[/\ABearer\s+(.+)\z/, 1]
          end

          # Smoke-test bypass credential. Deliberately a SEPARATE header and
          # secret from the dispatch bearer: the production Make scenario holds
          # only the bearer, so it can never obtain a frequency bypass even if a
          # scenario were edited to send the flag. Absence of the header is the
          # normal case and is not an error.
          def test_bypass_token_valid?
            expected = ENV["MAKE_PUSH_TEST_BYPASS_TOKEN"].to_s
            provided = request.headers["X-Push-Test-Token"].to_s
            return false if expected.blank? || provided.blank?

            ActiveSupport::SecurityUtils.secure_compare(expected, provided)
          end

          def allowed_dispatch_tokens
            [
              ENV["MAKE_PUSH_DISPATCH_TOKEN"],
              ENV["MAKE_PUSH_DISPATCH_TOKEN_CURRENT"],
              ENV["MAKE_PUSH_DISPATCH_TOKEN_PREVIOUS"]
            ].compact_blank
          end

          def reject_forbidden_fields
            raw = request.request_parameters
            return unless raw.is_a?(Hash) && FORBIDDEN_FIELDS.any? { |field| raw.key?(field) }

            render json: { status: "skipped", reason: "invalid_payload", detail: "forbidden_token_field", sent: false },
                   status: :unprocessable_entity
          end

          def enforce_body_size
            length = request.content_length.to_i
            return if length <= MAX_BODY_BYTES

            render json: { status: "skipped", reason: "invalid_payload", detail: "body_too_large", sent: false },
                   status: :payload_too_large
          end

          def require_https_in_production
            return unless Rails.env.production?
            return if request.ssl?

            head :forbidden
          end
        end
      end
    end
  end
end

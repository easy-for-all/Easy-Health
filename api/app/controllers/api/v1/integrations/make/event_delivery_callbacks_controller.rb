module Api
  module V1
    module Integrations
      module Make
        class EventDeliveryCallbacksController < ActionController::API
          ALLOWED_STATUSES = %w[received routed filtered completed failed].freeze
          SENSITIVE_KEY_PATTERN = /(password|token|secret|authorization|card|stripe|cpf|ssn|cvv|cvc|dsn|api_key|access_key)/i

          before_action :verify_bearer_token

          def create
            payload = request.request_parameters.with_indifferent_access
            status = payload[:status].to_s
            return render json: { error: "invalid_status" }, status: :unprocessable_entity unless ALLOWED_STATUSES.include?(status)

            delivery = find_delivery(payload)
            return render json: { error: "event_delivery_not_found" }, status: :not_found unless delivery

            callback_at = Time.current
            ::Make::UserEventReconciler.call(
              user_event: delivery,
              status: status,
              message: payload[:message],
              execution_id: payload[:execution_id],
              callback_at: callback_at
            )
            delivery.reload.update!(
              metadata: callback_metadata(delivery, payload, callback_at)
            )

            render json: { success: true }
          end

          private

          def verify_bearer_token
            expected = ENV["MAKE_DELIVERY_CALLBACK_TOKEN"].to_s
            if expected.blank?
              Rails.logger.error("[Make::EventDeliveryCallbacks] MAKE_DELIVERY_CALLBACK_TOKEN not configured")
              head :internal_server_error and return
            end

            provided = bearer_token
            return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(expected, provided)

            head :unauthorized
          end

          def bearer_token
            request.headers["Authorization"].to_s[/\ABearer\s+(.+)\z/, 1]
          end

          def find_delivery(payload)
            if payload[:idempotency_key].present?
              delivery = UserEvent.where(idempotency_key: payload[:idempotency_key].to_s).order(created_at: :desc).first
              return delivery if delivery
            end

            event_id = payload[:event_id].presence
            delivery = UserEvent.find_by(id: event_id) if event_id
            return delivery if delivery

            return nil if payload[:event_name].blank? || event_id.blank?

            UserEvent.find_by(id: event_id, event_name: payload[:event_name].to_s)
          end

          def callback_metadata(delivery, payload, callback_at)
            metadata = delivery.metadata.is_a?(Hash) ? delivery.metadata.deep_dup : {}
            metadata["last_make_callback"] = sanitize_metadata(
              {
                "status" => payload[:status],
                "scenario" => payload[:scenario],
                "execution_id" => payload[:execution_id],
                "occurred_at" => payload[:occurred_at],
                "message" => payload[:message],
                "received_at" => callback_at.iso8601
              }.compact
            )
            metadata
          end

          def sanitize_metadata(value)
            case value
            when Hash
              value.each_with_object({}) do |(key, child), result|
                next if key.to_s.match?(SENSITIVE_KEY_PATTERN)

                result[key.to_s] = sanitize_metadata(child)
              end
            when Array
              value.map { |child| sanitize_metadata(child) }
            else
              value
            end
          end
        end
      end
    end
  end
end

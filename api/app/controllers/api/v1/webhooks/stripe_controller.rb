module Api
  module V1
    module Webhooks
      class StripeController < ActionController::API
        def create
          secret = ENV["STRIPE_WEBHOOK_SECRET"]
          unless secret.present?
            Rails.logger.error("[Stripe] STRIPE_WEBHOOK_SECRET not configured")
            head :internal_server_error and return
          end

          payload    = request.body.read
          sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

          StripeWebhookService.call(payload: payload, sig_header: sig_header, secret: secret)
          delivery_ok
          head :ok
        rescue Stripe::SignatureVerificationError => e
          Rails.logger.warn("[Stripe] signature verification failed: #{e.message}")
          # Not counted as an integration failure: an unsigned request is a
          # rejected caller, not a broken Stripe pipeline. Counting it would let
          # anyone on the internet open an incident by POSTing garbage.
          head :bad_request
        rescue JSON::ParserError => e
          Rails.logger.warn("[Stripe] invalid JSON payload: #{e.message}")
          head :bad_request
        rescue => e
          Rails.logger.error("[Stripe] unexpected error: #{e.class}: #{e.message}")
          Rails.logger.error(e.backtrace.first(10).join("\n"))
          Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
          delivery_failed(e.class.name)
          head :internal_server_error
        end

        private

        def delivery_ok
          Observability::Context.integration_key = "stripe"
          Observability::Heartbeat.succeeded!("stripe_webhook_processing")
          Observability::Events.integration_delivery_succeeded(integration: "stripe")
        end

        def delivery_failed(error_code)
          Observability::Context.integration_key = "stripe"
          Observability::Heartbeat.failed!("stripe_webhook_processing", error_code: error_code)
          Observability::Events.integration_delivery_failed(integration: "stripe", error_code: error_code)
        end
      end
    end
  end
end

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
          head :ok
        rescue Stripe::SignatureVerificationError => e
          Rails.logger.warn("[Stripe] signature verification failed: #{e.message}")
          head :bad_request
        rescue JSON::ParserError => e
          Rails.logger.warn("[Stripe] invalid JSON payload: #{e.message}")
          head :bad_request
        rescue => e
          Rails.logger.error("[Stripe] unexpected error: #{e.class}: #{e.message}")
          Rails.logger.error(e.backtrace.first(10).join("\n"))
          head :internal_server_error
        end
      end
    end
  end
end

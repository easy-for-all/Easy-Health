module Api
  module V1
    module Webhooks
      class StripeController < ActionController::API
        def create
          payload    = request.body.read
          sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

          StripeWebhookService.call(payload: payload, sig_header: sig_header)
          head :ok
        rescue Stripe::SignatureVerificationError => e
          Rails.logger.warn("Stripe webhook signature verification failed: #{e.message}")
          head :bad_request
        rescue => e
          Rails.logger.error("Stripe webhook error: #{e.message}")
          head :internal_server_error
        end
      end
    end
  end
end

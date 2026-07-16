module Api
  module V1
    module Analytics
      # Ingestion endpoint for product analytics events.
      #
      # Auth is OPTIONAL: it accepts anonymous_id before login (inherits from
      # ApplicationController, not BaseController, so it does not force
      # authenticate_user!). When a Devise session cookie is present, current_user
      # is used server-side — the client never asserts its own user_id.
      class EventsController < ApplicationController
        MAX_BATCH_SIZE = ::Analytics::Ingestion::MAX_BATCH_SIZE

        def create
          events = events_param
          if events.blank?
            render json: { error: "events required" }, status: :bad_request
            return
          end

          if events.size > MAX_BATCH_SIZE
            render json: { error: "batch too large (max #{MAX_BATCH_SIZE})" }, status: :content_too_large
            return
          end

          result = ::Analytics::Ingestion.new(user: current_user, events: events).call

          render json: {
            accepted: result.accepted,
            persisted: result.persisted,
            skipped: result.skipped,
            rejected: result.rejected
          }, status: :accepted
        rescue StandardError => e
          # Analytics must never break the client — swallow and report.
          Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
          Rails.logger.error("[analytics] ingestion error: #{e.class}: #{e.message}")
          head :accepted
        end

        private

        def events_param
          raw = params[:events]
          return [] unless raw.is_a?(Array) || raw.respond_to?(:to_a)

          raw.to_a
        end
      end
    end
  end
end

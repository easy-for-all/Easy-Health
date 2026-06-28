module Api
  module V1
    module Webhooks
      module Make
        class RelationshipMessagesController < ActionController::API
          before_action :verify_make_secret

          def create
            result = RelationshipMessageService.record_from_make!(
              payload: request.request_parameters
            )

            if result.success?
              render json: { status: "ok", id: result.record.id }, status: :created
            else
              http_status = result.error == "user_not_found" ? :not_found : :unprocessable_entity
              render json: { status: "error", error: result.error }, status: http_status
            end
          rescue => e
            Rails.logger.error("[Make::RelationshipMessages] #{e.class}: #{e.message}")
            Rails.logger.error(e.backtrace.first(5).join("\n"))
            head :internal_server_error
          end

          private

          def verify_make_secret
            secret   = ENV["MAKE_INBOUND_WEBHOOK_SECRET"]
            provided = request.headers["X-Make-Secret"]

            unless secret.present?
              Rails.logger.error("[Make::RelationshipMessages] MAKE_INBOUND_WEBHOOK_SECRET not configured")
              head :internal_server_error and return
            end

            unless provided.present? && ActiveSupport::SecurityUtils.secure_compare(secret, provided)
              head :unauthorized and return
            end
          end
        end
      end
    end
  end
end

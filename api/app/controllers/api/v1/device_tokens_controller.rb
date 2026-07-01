module Api
  module V1
    class DeviceTokensController < BaseController
      def create
        token    = params.require(:token)
        platform = params.fetch(:platform, "android")

        unless DeviceToken::PLATFORMS.include?(platform)
          return render json: { error: "Invalid platform" }, status: :unprocessable_entity
        end

        device_token = DeviceToken.find_or_initialize_by(token: token)
        device_token.user     = current_user
        device_token.platform = platform

        if device_token.save
          head :ok
        else
          render json: { errors: device_token.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end
end

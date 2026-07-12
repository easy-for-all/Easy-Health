module Api
  module V1
    class DeviceTokensController < BaseController
      before_action :set_device_token, only: [:update, :destroy]

      # Upsert by token. Re-registering the same token refreshes its metadata and
      # re-enables it (a token can come back after being invalidated).
      def create
        token    = params.require(:token)
        platform = params.fetch(:platform, "android")

        unless DeviceToken::PLATFORMS.include?(platform)
          return render json: { error: "Invalid platform" }, status: :unprocessable_entity
        end

        device_token = DeviceToken.find_or_initialize_by(token: token)
        device_token.assign_attributes(
          user: current_user,
          platform: platform,
          enabled: true,
          invalidated_at: nil,
          invalidation_reason: nil,
          last_seen_at: Time.current,
          token_refreshed_at: Time.current,
          **device_metadata
        )

        if device_token.save
          render json: { id: device_token.id, enabled: device_token.enabled }, status: :ok
        else
          render json: { errors: device_token.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @device_token.update(device_metadata.merge(last_seen_at: Time.current))
          render json: { id: @device_token.id, enabled: @device_token.enabled }
        else
          render json: { errors: @device_token.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # Logical disable (keeps history). Used when the user turns push off.
      def destroy
        @device_token.invalidate!("user_removed")
        head :no_content
      end

      private

      def set_device_token
        # Scoped to current_user — a user can never touch another user's device.
        @device_token = current_user.device_tokens.find(params[:id])
      end

      def device_metadata
        params.permit(:device_identifier, :app_version, :os_version, :permission_status)
              .to_h
              .symbolize_keys
      end
    end
  end
end

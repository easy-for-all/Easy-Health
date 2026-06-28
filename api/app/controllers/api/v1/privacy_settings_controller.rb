module Api
  module V1
    class PrivacySettingsController < BaseController
      def show
        render json: privacy_json
      end

      def update
        permitted = params.permit(:profile_visibility, :community_enabled, :account_type, :marketing_consent)

        if permitted[:account_type].present? && !User::ACCOUNT_TYPES.include?(permitted[:account_type])
          return render_error("Invalid account type")
        end

        if permitted[:profile_visibility].present? && !User::PROFILE_VISIBILITIES.include?(permitted[:profile_visibility])
          return render_error("Invalid profile visibility")
        end

        current_user.update!(permitted.to_h.compact)
        render json: privacy_json
      rescue ActiveRecord::RecordInvalid => e
        render_error(e.record.errors.full_messages.to_sentence)
      end

      private

      def privacy_json
        {
          account_type:       current_user.account_type,
          profile_visibility: current_user.profile_visibility,
          community_enabled:  current_user.community_enabled,
          marketing_consent:  current_user.marketing_consent,
          referral_code:      current_user.referral_code
        }
      end
    end
  end
end

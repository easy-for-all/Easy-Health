module Api
  module V1
    class ReferralCodesController < BaseController
      # GET /api/v1/referral_code
      def show
        render json: {
          code:       current_user.referral_code,
          uses_count: 0,
        }
      end
    end
  end
end

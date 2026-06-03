module Api
  module V1
    class PersonalAccountsController < BaseController
      def activate
        current_user.update!(account_type: "personal_trainer")
        render json: {
          message: "Personal trainer account activated",
          account_type: current_user.account_type
        }
      rescue ActiveRecord::RecordInvalid => e
        render_error(e.record.errors.full_messages.to_sentence)
      end
    end
  end
end

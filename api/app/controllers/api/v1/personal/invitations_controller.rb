module Api
  module V1
    module Personal
      class InvitationsController < BaseController
        FRONTEND_URL = ENV.fetch("FRONTEND_URL", "http://localhost:3000")

        def create
          code = PersonalInviteService.new(current_user).call
          invite_url = "#{FRONTEND_URL}/join/#{code}"

          render json: {
            invitation_code: code,
            invite_url: invite_url,
            expires_at: PersonalClientRelationship::INVITATION_TTL.from_now
          }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end

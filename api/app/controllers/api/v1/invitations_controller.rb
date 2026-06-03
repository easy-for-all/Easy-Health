module Api
  module V1
    class InvitationsController < BaseController
      def accept
        relationship = PersonalClientRelationship.find_by(invitation_code: params[:code])

        if relationship.nil?
          return render_error("Invitation not found", status: :not_found)
        end

        if relationship.invitation_expired?
          return render_error("Invitation has expired", status: :unprocessable_entity)
        end

        if relationship.client_id.present?
          return render_error("Invitation already used", status: :unprocessable_entity)
        end

        if relationship.personal_id == current_user.id
          return render_error("You cannot accept your own invitation", status: :unprocessable_entity)
        end

        relationship.update!(client: current_user)
        relationship.activate!

        render json: {
          message: "You are now connected to #{relationship.personal.name}",
          personal_name: relationship.personal.name,
          relationship_id: relationship.id
        }
      rescue ActiveRecord::RecordInvalid => e
        render_error(e.record.errors.full_messages.to_sentence)
      end
    end
  end
end

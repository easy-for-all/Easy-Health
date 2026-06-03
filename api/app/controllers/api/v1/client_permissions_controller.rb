module Api
  module V1
    class ClientPermissionsController < BaseController
      def show
        relationship = active_relationship
        return render_error("No active trainer relationship found", status: :not_found) unless relationship

        render json: {
          personal_name: relationship.personal.name,
          relationship_id: relationship.id,
          permissions: serialize_permissions(relationship.client_permission)
        }
      end

      def update
        relationship = active_relationship
        return render_error("No active trainer relationship found", status: :not_found) unless relationship

        perms = relationship.client_permission
        allowed_keys = ClientPermission::PERMISSION_KEYS - ["can_view_exams"]

        patch = params.permit(*allowed_keys).to_h.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }

        perms.update!(patch)
        render json: {
          permissions: serialize_permissions(perms)
        }
      rescue ActiveRecord::RecordInvalid => e
        render_error(e.record.errors.full_messages.to_sentence)
      end

      private

      def active_relationship
        PersonalClientRelationship
          .where(client: current_user, status: "active")
          .includes(:personal, :client_permission)
          .first
      end

      def serialize_permissions(perms)
        return {} unless perms
        ClientPermission::PERMISSION_KEYS.each_with_object({}) do |key, h|
          h[key] = perms.public_send(key)
        end
      end
    end
  end
end

module Api
  module V1
    module Personal
      class ClientsController < BaseController
        def index
          relationships = current_user.personal_client_relationships
                                      .where(status: "active")
                                      .includes(:client, :client_permission)
                                      .order(started_at: :desc)

          render json: { clients: relationships.map { |r| serialize_client(r) } }
        end

        def show
          relationship = find_active_relationship(params[:id])
          return render_error("Client not found", status: :not_found) unless relationship

          policy = PersonalAccessPolicy.new(current_user, relationship.client)
          client = relationship.client
          adherence = ClientAdherenceService.new(client).summary

          data = {
            relationship_id: relationship.id,
            client_id: client.id,
            name: client.name,
            avatar_url: client.avatar.attached? ? blob_path(client.avatar) : nil,
            started_at: relationship.started_at,
            permissions: serialize_permissions(relationship.client_permission),
            adherence: policy.can_view?(:can_view_adherence) ? adherence : nil,
            has_active_plan: client.active_workout_plan.present?
          }

          if policy.can_view?(:can_view_completed_workouts)
            data[:recent_sessions] = client.workout_sessions
                                           .order(completed_at: :desc)
                                           .limit(5)
                                           .map { |s| { id: s.id, completed_at: s.completed_at, duration: s.duration_minutes } }
          end

          render json: { client: data }
        end

        def destroy
          relationship = find_active_relationship(params[:id])
          return render_error("Client not found", status: :not_found) unless relationship

          relationship.update!(status: "removed")
          render json: { message: "Client removed" }
        end

        def assign_plan
          relationship = find_active_relationship(params[:client_id])
          return render_error("Client not found", status: :not_found) unless relationship

          client = relationship.client

          # Deactivate existing active plan
          client.workout_plans.where(active: true).update_all(active: false)

          # Create plan skeleton — personal fills days separately
          plan = client.workout_plans.create!(active: true)

          render json: {
            message: "Plan created for client",
            plan_id: plan.id
          }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.record.errors.full_messages.to_sentence)
        end

        private

        def find_active_relationship(client_id)
          current_user.personal_client_relationships
                      .where(status: "active")
                      .includes(:client, :client_permission)
                      .find_by(client_id: client_id)
        end

        def serialize_client(relationship)
          client = relationship.client
          adherence = ClientAdherenceService.new(client)

          {
            relationship_id: relationship.id,
            client_id: client.id,
            name: client.name,
            avatar_url: client.avatar.attached? ? blob_path(client.avatar) : nil,
            status: relationship.status,
            started_at: relationship.started_at,
            weekly_adherence: adherence.weekly_adherence,
            last_session_at: adherence.last_session_at,
            days_without_training: adherence.days_without_training,
            inactive_alert: adherence.inactive_alert?,
            needs_new_plan: adherence.needs_new_plan?,
            has_active_plan: client.active_workout_plan.present?
          }
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
end

module Api
  module V1
    module Personal
      class DashboardController < BaseController
        def show
          relationships = current_user.personal_client_relationships
                                      .where(status: "active")
                                      .includes(:client, :client_permission)

          clients_data = relationships.map { |r| client_summary(r) }

          active_count     = clients_data.count
          inactive_7d      = clients_data.count { |c| c[:days_without_training].to_i >= 7 }
          high_adherence   = clients_data.count { |c| c[:weekly_adherence].to_i >= 80 }
          needs_plan       = clients_data.count { |c| c[:needs_new_plan] }

          render json: {
            dashboard: {
              active_clients:    active_count,
              inactive_7_days:   inactive_7d,
              high_adherence:    high_adherence,
              needs_new_plan:    needs_plan,
              pending_invites:   current_user.personal_client_relationships.invited.count
            },
            clients: clients_data
          }
        end

        private

        def client_summary(relationship)
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
      end
    end
  end
end

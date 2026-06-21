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
                                           .limit(10)
                                           .map { |s| { id: s.id, completed_at: s.completed_at, duration: s.duration_minutes } }
            data[:weekly_frequency] = weekly_frequency_chart(client)
          end

          data[:next_workout] = next_workout_for(client)

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

        def weekly_frequency_chart(client)
          (0..11).map do |weeks_ago|
            start_of_week = weeks_ago.weeks.ago.beginning_of_week
            end_of_week   = start_of_week.end_of_week
            count = client.workout_sessions
              .where(completed_at: start_of_week..end_of_week)
              .count
            { week: start_of_week.strftime("%d/%m"), sessions: count }
          end.reverse
        end

        def next_workout_for(client)
          plan = client.active_workout_plan
          return nil unless plan

          today_dow = Date.today.wday
          upcoming = plan.workout_days
            .where.not(day_of_week: nil)
            .order(:day_of_week)
            .find { |d| d.day_of_week >= today_dow }
          upcoming ||= plan.workout_days.where.not(day_of_week: nil).order(:day_of_week).first
          return nil unless upcoming

          {
            id:           upcoming.id,
            name:         upcoming.custom_name.presence || "Treino #{upcoming.day_of_week}",
            day_of_week:  upcoming.day_of_week,
          }
        end

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

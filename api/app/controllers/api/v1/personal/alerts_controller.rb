module Api
  module V1
    module Personal
      class AlertsController < BaseController
        before_action :require_personal_trainer!

        def index
          alerts = PersonalAlert.for_personal(current_user).limit(50)
          render json: {
            alerts: alerts.map { |a| alert_json(a) },
            unread_count: PersonalAlert.for_personal(current_user).unread.count
          }
        end

        def mark_read
          alert = PersonalAlert.for_personal(current_user).find_by(id: params[:id])
          return render_error("Alert not found", status: :not_found) unless alert

          alert.mark_read!
          render json: {
            alert: alert_json(alert),
            unread_count: PersonalAlert.for_personal(current_user).unread.count
          }
        end

        private

        def alert_json(alert)
          {
            id:        alert.id,
            kind:      alert.kind,
            title:     alert.title,
            body:      alert.body,
            unread:    alert.unread?,
            time:      time_ago(alert.created_at),
            client_id: alert.client_id,
          }
        end

        def time_ago(time)
          diff = (Time.current - time).to_i
          if diff < 3600
            "#{diff / 60}min atrás"
          elsif diff < 86_400
            "#{diff / 3600}h atrás"
          else
            "#{diff / 86_400}d atrás"
          end
        end
      end
    end
  end
end

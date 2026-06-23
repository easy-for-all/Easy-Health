module Api
  module V1
    class HealthController < ApplicationController
      def show
        db_ok = ActiveRecord::Base.connection.execute("SELECT 1").any? rescue false
        status = db_ok ? :ok : :service_unavailable
        render json: { status: db_ok ? "ok" : "degraded", db: db_ok, time: Time.current }, status: status
      end
    end
  end
end

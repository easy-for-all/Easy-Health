module Api
  module V1
    module Experiments
      # Records which variant an installation was assigned to.
      #
      # Auth is OPTIONAL (inherits from ApplicationController, not BaseController):
      # the pre-auth Android experiment is decided before an account exists. The
      # row is deliberately kept user_id NULL even when a session cookie is
      # present — the (experiment_key, installation_id) unique index only covers
      # user_id IS NULL, so stamping a user here would silently disable the very
      # dedup this endpoint depends on. The user is reachable through
      # app_installations.user_id, which is the join the admin panel uses.
      #
      # THE CLIENT DECIDES THE VARIANT, THE DATABASE DECIDES WHO WON. Assignment
      # is a synchronous local hash (the UI cannot wait on a round trip without
      # flickering between two different flows), so this endpoint never computes
      # a variant. It records the first one and, on a repeat with a different
      # value, answers with the one already stored: that is the one whose
      # exposure was already measured.
      #
      # Never blocks the client: always 202, every failure swallowed. A lost
      # assignment write costs a row of cross-checking; the events pipeline is
      # what actually feeds the funnel.
      class AssignmentsController < ApplicationController
        MAX_INSTALLATION_ID_BYTES = 128

        # POST /api/v1/experiments/assignments
        def create
          key = params[:experiment_key].to_s
          variant = params[:variant].to_s
          installation_id = params[:installation_id].to_s.strip

          return render_ignored("unknown_experiment") unless ::Analytics::ExperimentRegistry.known?(key)
          return render_ignored("invalid_variant") unless ::Analytics::ExperimentRegistry.valid_variant?(key, variant)
          return render_ignored("invalid_installation_id") if invalid_installation_id?(installation_id)

          record = upsert(key, variant, installation_id)
          return render_ignored("write_unavailable") if record.nil?

          render json: {
            status: record.variant == variant ? "assigned" : "conflict",
            experiment_key: key,
            variant: record.variant
          }, status: :accepted
        rescue StandardError => e
          Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
          Rails.logger.error("[experiments] assignment error: #{e.class}: #{e.message}")
          render_ignored("internal_error")
        end

        private

        # Read-then-write, with the unique index as the arbiter of the race. The
        # rescue is not defensive noise: two tabs of the same WebView finishing
        # the onboarding at once is exactly the case the index exists for, and
        # the loser must read the winner's row rather than fail.
        def upsert(key, variant, installation_id)
          scope = ::Analytics::ExperimentAssignment.for_experiment(key)
                                                   .for_installation(installation_id)
                                                   .where(user_id: nil)

          existing = scope.first
          return existing if existing

          ::Analytics::ExperimentAssignment.create!(
            experiment_key: key,
            variant: variant,
            installation_id: installation_id,
            assigned_at: Time.current
          )
        rescue ActiveRecord::RecordNotUnique
          scope.first
        end

        def invalid_installation_id?(installation_id)
          installation_id.blank? || installation_id.bytesize > MAX_INSTALLATION_ID_BYTES
        end

        # Not an error the client can act on: the variant it is already using
        # stays in force. Reported so a misconfigured build is visible in logs
        # instead of looking like silence.
        def render_ignored(reason)
          render json: { status: "ignored", reason: reason }, status: :accepted
        end
      end
    end
  end
end

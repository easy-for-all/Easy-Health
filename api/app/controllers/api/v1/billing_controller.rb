module Api
  module V1
    class BillingController < BaseController
      VALID_PLANS = %w[pro_monthly pro_yearly].freeze

      prepend_before_action :render_authentication_required, only: [:checkout], unless: :user_signed_in?

      def checkout
        plan = params[:plan].to_s
        platform = billing_platform

        result = StripeCheckoutService.call(
          user: current_user,
          plan: plan,
          request_id: request.request_id,
          platform: platform
        )

        UserEventService.track(
          user: current_user,
          event_name: "checkout_session_created",
          metadata: { plan_type: plan, platform: platform, request_id: request.request_id },
          idempotency_key: "checkout_session_created:#{current_user.id}:#{result[:session_id]}"
        )

        render json: result
      rescue StripeCheckoutService::BillingError => e
        track_checkout_failure(plan: plan, platform: platform, code: e.code)
        report_billing_exception(e) unless e.code == "billing_invalid_plan"
        log_billing_failure(plan: plan, platform: platform, error: e)
        render_billing_error(code: e.code, message: e.public_message, status: e.status)
      rescue StandardError => e
        track_checkout_failure(plan: plan, platform: platform, code: "billing_checkout_creation_failed")
        report_billing_exception(e)
        log_billing_failure(plan: plan, platform: platform, error: e, code: "billing_checkout_creation_failed")
        render_billing_error(
          code: "billing_checkout_creation_failed",
          message: "Não foi possível iniciar o checkout.",
          status: :bad_gateway
        )
      end

      def portal
        portal_url = StripeCustomerPortalService.call(user: current_user)
        render json: { portal_url: portal_url }
      rescue ArgumentError => e
        render_error(e.message, status: :unprocessable_entity)
      rescue Stripe::StripeError => e
        render_error(e.message, status: :bad_gateway)
      end

      def status
        render json: current_user.billing_status
      end

      def change_plan
        new_plan = params[:plan]
        unless VALID_PLANS.include?(new_plan)
          return render_error("Invalid plan. Must be one of: #{VALID_PLANS.join(', ')}")
        end

        sub = StripePlanChangeService.call(user: current_user, new_plan: new_plan)
        render json: { message: "Plan updated successfully", subscription: billing_sub_json(sub) }
      rescue ArgumentError => e
        render_error(e.message, status: :unprocessable_entity)
      rescue Stripe::StripeError => e
        render_error(e.message, status: :bad_gateway)
      end

      def cancel_subscription
        sub = current_user.subscription
        return render_error("No active subscription", status: :unprocessable_entity) if sub&.stripe_subscription_id.blank?

        Stripe::Subscription.update(sub.stripe_subscription_id, cancel_at_period_end: true)
        sub.update!(cancel_at_period_end: true)
        UserEventService.track(
          user: current_user,
          event: :subscription_canceled,
          metadata: {
            subscription_id: sub.id,
            stripe_subscription_id: sub.stripe_subscription_id,
            cancel_at_period_end: true
          },
          idempotency_key: "subscription_canceled:#{sub.id}:scheduled"
        )

        render json: { message: "Subscription will be canceled at period end", subscription: billing_sub_json(sub) }
      rescue Stripe::StripeError => e
        render_error(e.message, status: :bad_gateway)
      end

      def reactivate_subscription
        sub = current_user.subscription
        return render_error("No subscription found", status: :unprocessable_entity) if sub&.stripe_subscription_id.blank?

        Stripe::Subscription.update(sub.stripe_subscription_id, cancel_at_period_end: false)
        sub.update!(cancel_at_period_end: false)

        render json: { message: "Subscription reactivated", subscription: billing_sub_json(sub) }
      rescue Stripe::StripeError => e
        render_error(e.message, status: :bad_gateway)
      end

      def sync
        result = StripeSyncService.call(user: current_user)
        if result.success
          render json: { message: result.message, subscription: billing_sub_json(result.subscription) }
        else
          render_error(result.message, status: :unprocessable_entity)
        end
      end

      private

      def render_authentication_required
        render_billing_error(
          code: "authentication_required",
          message: "Sua sessão expirou. Entre novamente para continuar.",
          status: :unauthorized
        )
      end

      def render_billing_error(code:, message:, status:)
        render json: {
          error: {
            code: code,
            message: message,
            request_id: request.request_id
          },
          error_code: code,
          message: message
        }, status: status
      end

      def billing_platform
        params[:platform].presence ||
          request.headers["X-EasyHealth-Platform"].presence ||
          (request.user_agent.to_s.include?("; wv") ? "android_webview" : "web")
      end

      def track_checkout_failure(plan:, platform:, code:)
        return unless current_user

        UserEventService.track(
          user: current_user,
          event_name: "checkout_failed",
          metadata: { plan_type: plan, platform: platform, error_code: code, request_id: request.request_id },
          idempotency_key: "checkout_failed:#{current_user.id}:#{request.request_id}"
        )
      end

      def report_billing_exception(error)
        Sentry.capture_exception(error) if defined?(Sentry) && Sentry.initialized?
      end

      def log_billing_failure(plan:, platform:, error:, code: nil)
        payload = {
          request_id: request.request_id,
          user_id: current_user&.id,
          plan: plan,
          platform: platform,
          stage: "checkout_controller",
          result: "failure",
          error_code: code || (error.respond_to?(:code) ? error.code : nil),
          exception_class: error.class.name
        }
        Rails.logger.error("[BillingCheckout] #{payload.compact.to_json}")
      end

      def billing_sub_json(sub)
        {
          plan: sub.plan_name,
          status: sub.status,
          paid: sub.paid_plan?,
          trial_end: sub.trial_end,
          current_period_end: sub.current_period_end,
          cancel_at_period_end: sub.cancel_at_period_end
        }
      end
    end
  end
end

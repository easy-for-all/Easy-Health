module Api
  module V1
    class BillingController < BaseController
      VALID_PLANS = %w[pro_monthly pro_yearly].freeze

      def checkout
        plan = params[:plan]
        unless VALID_PLANS.include?(plan)
          return render_error("Invalid plan. Must be one of: #{VALID_PLANS.join(', ')}")
        end

        checkout_url = StripeCheckoutService.call(user: current_user, plan: plan)
        render json: { checkout_url: checkout_url }
      rescue Stripe::StripeError => e
        render_error(e.message, status: :bad_gateway)
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

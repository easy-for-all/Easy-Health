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
    end
  end
end

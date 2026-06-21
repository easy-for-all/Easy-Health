module RequiresActiveAccess
  extend ActiveSupport::Concern

  private

  def require_active_access!
    return if current_user.has_active_access?
    render json: {
      error: "trial_expired",
      message: "Seu período de teste gratuito terminou. Assine para continuar."
    }, status: :payment_required
  end
end

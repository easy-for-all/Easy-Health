class ApplicationController < ActionController::API
  include ActionController::Cookies

  before_action :configure_permitted_parameters, if: :devise_controller?
  after_action :set_request_id_header

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
  end

  private

  def set_request_id_header
    response.headers["X-Request-Id"] = request.request_id
  end

  def require_admin!
    unless current_user&.admin?
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end

  def blob_path(attachment)
    return nil unless attachment.attached?
    Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
  end

  def set_auth_indicator_cookie
    cookies[:_eh_auth] = {
      value: "1",
      domain: ".easyhealth.art",
      path: "/",
      secure: Rails.env.production?,
      httponly: false,
      same_site: :lax
    }
  end

  def delete_auth_indicator_cookie
    cookies.delete(:_eh_auth, domain: ".easyhealth.art", path: "/")
  end

  def user_json(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      admin: user.admin?,
      created_at: user.created_at,
      first_workout_completed_at: user.first_workout_completed_at,
      avatar_url: blob_path(user.avatar),
      billing_status: user.billing_status,
      account_type: user.account_type,
      profile_visibility: user.profile_visibility,
      community_enabled: user.community_enabled,
      referral_code: user.referral_code
    }
  end
end

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
end

class ApplicationController < ActionController::API
  include ActionController::Cookies

  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
  end

  private

  def blob_path(attachment)
    return nil unless attachment.attached?
    Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
  end
end

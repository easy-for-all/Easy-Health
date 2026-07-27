require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Middleware must be a real constant when the stack is assembled below, and
# autoloaded constants cannot be referenced during initialization — so this one
# directory is required explicitly and excluded from autoload_lib.
require_relative "../lib/middleware/observability_request_context"

module App
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks middleware])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Filter sensitive params from logs and error reporters
    config.filter_parameters += %i[password password_confirmation token code code_digest secret key dsn authorization]

    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
      key: "_easy_health_session",
      same_site: :lax,
      secure: Rails.env.production?

    # Inserted after RequestId so request.request_id is already populated, and
    # after the Executor so CurrentAttributes are not reset out from under it.
    # Rack::Cors sits before position 0 and Rack::Attack is appended by its own
    # initializer, so a rack-attack 429 is still counted here.
    config.middleware.insert_after ActionDispatch::RequestId, ObservabilityRequestContext
  end
end

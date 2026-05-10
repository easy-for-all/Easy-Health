require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.assume_ssl = true
  config.session_store :cookie_store,
    key: "_easy_health_session",
    same_site: :lax,
    secure: true

  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = false

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]

  config.active_storage.service = :local
end

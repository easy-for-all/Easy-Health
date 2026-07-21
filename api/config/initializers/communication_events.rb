# Fail fast on a malformed communication_events.yml. In dev/test a bad config
# should stop the boot (and the test suite) so it never reaches production; in
# production we only log, to avoid a bad deploy taking the whole app down over a
# config that can be fixed forward.
Rails.application.config.after_initialize do
  CommunicationEvents.validate!
rescue CommunicationEvents::ConfigError => e
  raise unless Rails.env.production?

  Rails.logger.error("[CommunicationEvents] invalid config: #{e.message}")
end

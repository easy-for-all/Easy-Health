module Observability
  # Sends incident notifications to a generic webhook (Make, Slack relay, or
  # anything else that accepts JSON).
  #
  # OFF BY DEFAULT (OBSERVABILITY_ALERTS_ENABLED=false). Shipping an alerting
  # path that starts firing the moment it deploys is how teams learn to ignore
  # alerts; it gets turned on deliberately, after the thresholds have been
  # watched for a few days.
  #
  # PRIVACY: the payload carries an incident id, a check key, numbers and the
  # allow-listed dimensions. There is no user, no email, no installation id, and
  # no free-form error text — an alert is delivered to a third-party automation
  # platform, so it gets the strictest treatment of any sink here.
  module Notifier
    module_function

    # @return [Boolean] whether a notification was actually delivered
    def deliver(incident:, event:)
      return false unless Observability::Config.alerts_enabled?

      url = Observability::Config.alert_webhook_url
      if url.blank?
        Rails.logger.warn("[observability] alerts enabled but OBSERVABILITY_ALERT_WEBHOOK_URL is blank")
        return false
      end

      Observability::Notifiers::WebhookNotifier.new(url: url).call(
        payload: payload(incident: incident, event: event)
      )
    rescue StandardError => e
      Rails.logger.warn("[observability] notifier failed: #{e.class}")
      false
    end

    def payload(incident:, event:)
      {
        event: event,
        environment: Rails.env.to_s,
        incident: {
          # Internal primary key, not a person. Safe to echo back.
          id: incident.id,
          reference: "INC-#{incident.id}",
          title: incident.title,
          severity: incident.severity,
          status: incident.status,
          source: incident.source,
          check_key: incident.check_key,
          current_value: incident.current_value&.to_f,
          threshold_value: incident.threshold_value&.to_f,
          sample_size: incident.metadata.is_a?(Hash) ? incident.metadata["sample_size"] : nil,
          explanation: incident.description,
          dimensions: Observability::Fingerprint.canonical_dimensions(incident.dimensions),
          occurrence_count: incident.occurrence_count,
          detected_at: incident.first_detected_at&.iso8601,
          last_detected_at: incident.last_detected_at&.iso8601,
          resolved_at: incident.resolved_at&.iso8601,
          admin_url: admin_url
        }
      }
    end

    def admin_url
      base = ENV["FRONTEND_URL"].presence || "https://easyhealth.art"
      "#{base}/admin/observability"
    end
  end
end

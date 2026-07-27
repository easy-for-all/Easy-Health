module Observability
  # Turns a stream of check results into a small set of incidents a human can
  # act on: opening, deduplicating, escalating, auto-resolving and notifying.
  #
  # The deduplication is the point. A check runs every 15 minutes; a problem
  # that lasts a day would otherwise produce 96 identical alerts. Here it
  # produces one incident with occurrence_count = 96 and (with the default
  # 60-minute cooldown) about 24 notifications at most — and only if it keeps
  # getting worse.
  module IncidentManager
    module_function

    # Reconciles one check result against the incident table.
    # alerting  -> open or update
    # healthy   -> resolve whatever this check had open
    # insufficient_data -> do nothing at all (see below)
    def reconcile(result)
      return nil unless Observability::Config.enabled?

      fingerprint = fingerprint_for(result)

      if result.alerting?
        open_or_update(result, fingerprint)
      elsif result.healthy?
        resolve_by_fingerprint(fingerprint, reason: "check_recovered")
      end
      # insufficient_data deliberately does nothing: we could not measure, so we
      # can neither claim a problem nor claim recovery. Auto-resolving here
      # would silently close a real incident the moment traffic dried up.
      nil
    rescue StandardError => e
      Rails.logger.error("[observability] incident reconcile failed for #{result&.check_key}: #{e.class}")
      Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
      nil
    end

    def open_or_update(result, fingerprint = nil)
      fingerprint ||= fingerprint_for(result)
      existing = ObservabilityIncident.active.find_by(fingerprint: fingerprint)

      existing ? update_existing(existing, result) : open_new(result, fingerprint)
    end

    def open_new(result, fingerprint)
      incident = ObservabilityIncident.create!(
        fingerprint: fingerprint,
        source: "internal_check",
        check_key: result.check_key,
        title: title_for(result),
        description: result.explanation,
        severity: result.severity == "critical" ? "critical" : "warning",
        status: ObservabilityIncident::STATUS_OPEN,
        current_value: result.current_value,
        threshold_value: result.threshold_value,
        dimensions: Observability::Fingerprint.canonical_dimensions(result.dimensions),
        first_detected_at: Time.current,
        last_detected_at: Time.current,
        occurrence_count: 1,
        metadata: { definition: result.definition, unit: result.unit, sample_size: result.sample_size }.compact
      )

      Observability::Logger.emit(
        "incident_opened",
        level: incident.severity == "critical" ? :error : :warn,
        result: "opened",
        error_code: incident.check_key,
        metadata: { incident_id: incident.id, severity: incident.severity }
      )

      notify(incident, "observability_incident_opened")
      incident
    rescue ActiveRecord::RecordNotUnique
      # Lost a race against a concurrent run — the other one opened it.
      existing = ObservabilityIncident.active.find_by(fingerprint: fingerprint)
      existing ? update_existing(existing, result) : nil
    end

    def update_existing(incident, result)
      escalated = result.severity == "critical" && incident.severity != "critical"

      incident.update!(
        last_detected_at: Time.current,
        occurrence_count: incident.occurrence_count + 1,
        current_value: result.current_value,
        threshold_value: result.threshold_value,
        description: result.explanation,
        severity: escalated ? "critical" : incident.severity
      )

      Observability::Logger.emit(
        "incident_updated",
        level: :info,
        result: escalated ? "escalated" : "recurring",
        error_code: incident.check_key,
        metadata: { incident_id: incident.id, occurrence_count: incident.occurrence_count, severity: incident.severity }
      )

      # An escalation always notifies; a mere recurrence waits for the cooldown.
      notify(incident, escalated ? "observability_incident_escalated" : "observability_incident_opened", force: escalated)
      incident
    end

    def resolve_by_fingerprint(fingerprint, reason: "check_recovered")
      incident = ObservabilityIncident.active.find_by(fingerprint: fingerprint)
      return nil if incident.nil?

      resolve!(incident, resolved_by: reason)
    end

    def resolve!(incident, resolved_by: "auto")
      incident.update!(
        status: ObservabilityIncident::STATUS_RESOLVED,
        resolved_at: Time.current,
        resolved_by: resolved_by.to_s[0, 64]
      )

      Observability::Logger.emit(
        "incident_resolved",
        level: :info,
        result: "resolved",
        error_code: incident.check_key,
        metadata: {
          incident_id: incident.id,
          resolved_by: incident.resolved_by,
          duration_seconds: incident.duration_seconds
        }
      )

      # Resolution always notifies, cooldown or not: "it's over" is the one
      # message you never want suppressed.
      notify(incident, "observability_incident_resolved", force: true)
      incident
    end

    def acknowledge!(incident, acknowledged_by:)
      incident.update!(
        status: ObservabilityIncident::STATUS_ACKNOWLEDGED,
        acknowledged_at: Time.current,
        acknowledged_by: acknowledged_by.to_s[0, 64]
      )

      Observability::Logger.emit(
        "incident_updated",
        level: :info,
        result: "acknowledged",
        error_code: incident.check_key,
        metadata: { incident_id: incident.id, acknowledged_by: incident.acknowledged_by }
      )
      incident
    end

    # ── internals ────────────────────────────────────────────────────────────

    def fingerprint_for(result, source: "internal_check")
      Observability::Fingerprint.call(
        source: source,
        check_key: result.check_key,
        dimensions: result.dimensions
      )
    end

    def notify(incident, event, force: false)
      return unless force || cooldown_elapsed?(incident)

      delivered = Observability::Notifier.deliver(incident: incident, event: event)
      return unless delivered

      incident.update_columns(
        notification_count: incident.notification_count + 1,
        last_notified_at: Time.current,
        updated_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.warn("[observability] notify failed for incident #{incident.id}: #{e.class}")
    end

    def cooldown_elapsed?(incident)
      minutes = Observability::Config.alert_cooldown_minutes
      return true if minutes.zero?
      return true if incident.last_notified_at.nil?

      incident.last_notified_at <= Time.current - minutes.minutes
    end

    def title_for(result)
      suffix = result.dimensions.slice(*Observability::Fingerprint::ALLOWED_DIMENSIONS)
                     .map { |k, v| "#{k}=#{v}" }.join(" ")
      suffix.present? ? "#{result.check_key} (#{suffix})" : result.check_key
    end
  end
end

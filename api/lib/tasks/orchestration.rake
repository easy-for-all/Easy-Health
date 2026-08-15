# Versioned entry points for the orchestration event producers.
#
# These used to exist only as lines in a hand-maintained crontab on the VPS,
# which meant the schedule was not reproducible, not reviewable and not visible
# to anyone reading the repository. The tasks live here; scripts/cron/ installs
# them.
#
# Each job carries its own heartbeat, so "is this alive?" is answered by the
# admin panel rather than by reading the server's crontab.
namespace :orchestration do
  # Every ~15 minutes. The three producers are independent: one raising must not
  # stop the other two from running, or a single bad user silences the whole
  # journey until someone notices.
  desc "Run the 15-minute orchestration event producers (2h / 24h / scheduled reminder)"
  task run_15min: :environment do
    results = {}
    failures = {}

    {
      "first_workout_not_started_2h" => FirstWorkoutNotStarted2hJob,
      "first_workout_not_started_24h" => FirstWorkoutNotStarted24hJob,
      "scheduled_workout_reminder" => ScheduledWorkoutReminderSchedulerJob
    }.each do |name, job_class|
      results[name] = job_class.perform_now
    rescue StandardError => e
      # The job's own heartbeat already recorded the failure; this keeps the
      # loop going and puts the error in the cron log.
      failures[name] = "#{e.class}: #{e.message}"
      Rails.logger.error("[orchestration:run_15min] #{name} failed: #{e.class}: #{e.message}")
    end

    puts({ task: "orchestration:run_15min", at: Time.current.utc.iso8601,
           results: results, failures: failures }.to_json)
    abort("orchestration:run_15min: #{failures.keys.join(', ')} falhou(ram)") if failures.any?
  end

  # Once a day. This job already ran in production, but only from an unversioned
  # `rails runner "RelationshipDailyJob.new.perform"` line in the crontab, so
  # nothing in the repo declared it and it could silently differ per server.
  desc "Run the daily relationship journey (segments, trial, inactivity)"
  task relationship_daily: :environment do
    stats = RelationshipDailyJob.perform_now
    puts({ task: "orchestration:relationship_daily", at: Time.current.utc.iso8601, stats: stats }.to_json)
  end

  desc "Re-drive recent Make deliveries still pending from the cron sweep"
  task retry_pending_make: :environment do
    Observability::Context.for_task("make_pending_retry") do
      Observability::Heartbeat.track("make_pending_retry") do
        cutoff = 1.hour.ago
        scope = UserEvent.pending_make_delivery.where("created_at > ?", cutoff)
        stats = MakePendingDeliveryRetry.call(scope: scope, batch: true)

        puts({ task: "orchestration:retry_pending_make", at: Time.current.utc.iso8601, stats: stats }.to_json)
        stats
      end
    end
  end

  desc "Dispatch Make push requests deferred by quiet hours"
  task dispatch_deferred_pushes: :environment do
    Observability::Context.for_task("push_dispatch_deferred") do
      Observability::Heartbeat.track("push_dispatch_deferred") do
        limit = Integer(ENV.fetch("LIMIT", "500"), exception: false) || 500
        stats = Make::PushDispatchRequest.dispatch_deferred(limit: limit)
        puts({ task: "orchestration:dispatch_deferred_pushes", at: Time.current.utc.iso8601, stats: stats }.to_json)
        stats
      end
    end
  end

  desc "Print the health of every orchestration scheduler and any catalog drift"
  task status: :environment do
    schedules = {
      "relationship_daily_job" => "daily 08:00 #{CommunicationTime.default_zone_name}",
      "first_workout_not_started_2h" => "every 15 min",
      "first_workout_not_started_24h" => "every 15 min",
      "scheduled_workout_reminder" => "every 15 min",
      "make_pending_retry" => "every 15 min",
      "push_dispatch_deferred" => "every 15 min"
    }

    puts "SCHEDULERS"
    puts format("%-32s %-18s %-30s %-22s %-22s %-22s %s",
                "processo", "status", "schedule", "último início", "último sucesso", "última falha", "métricas")
    schedules.each_key do |key|
      record = ObservabilityHeartbeat.by_key(key).first
      if record.nil?
        puts format("%-32s %-18s %-30s %-22s %-22s %-22s %s",
                    key, "sem registro", schedules[key], "-", "-", "-", "rode bin/rails observability:heartbeats")
        next
      end

      puts format(
        "%-32s %-18s %-30s %-22s %-22s %-22s %s",
        key,
        record.status,
        schedules[key],
        record.last_started_at&.iso8601 || "nunca",
        record.last_succeeded_at&.iso8601 || "nunca",
        record.last_failed_at&.iso8601 || "nunca",
        (record.metadata.presence || {}).to_json
      )
    end

    puts "\nORCHESTRATION EVENTS (fonte de verdade: config/communication_events.yml)"
    puts CommunicationEvents.orchestration_event_names.join(", ")

    analytics_only = CommunicationEvents.analytics_only_event_names
    puts "\nNÃO-COMUNICAÇÃO (config/non_communication_events.yml): #{analytics_only.size} evento(s)"

    uncatalogued = CommunicationEvents.uncatalogued_event_names
    puts "\nUNCATALOGUED (sem decisão em nenhum catálogo)"
    if uncatalogued.any?
      puts "  #{uncatalogued.join(', ')}"
      puts "  → classifique em communication_events.yml ou non_communication_events.yml"
    else
      puts "  nenhum"
    end

    drift = MakeWebhookEligibility.allowlist_drift
    puts "\nALLOWLIST DRIFT"
    if drift[:env_only].any?
      puts "  env-only (sem entrada no YAML): #{drift[:env_only].join(', ')}"
    else
      puts "  nenhum"
    end

    puts "\nFLAGS"
    puts "  MAKE_WEBHOOK_ENABLED=#{MakeWebhookEligibility.enabled?}"
    puts "  SCHEDULED_WORKOUT_REMINDER_ENABLED=#{ScheduledWorkoutReminderEligibility.enabled?}"
    puts "  SCHEDULED_WORKOUT_REMINDER_LEAD_MINUTES=#{ScheduledWorkoutReminderSchedule.lead_minutes}"
    puts "  COMMUNICATION_DEFAULT_TIMEZONE=#{CommunicationTime.default_zone_name}"
    puts "  MAKE_PUSH_ORCHESTRATION_ENABLED=#{ENV.fetch('MAKE_PUSH_ORCHESTRATION_ENABLED', 'false')}"
    puts "  PUSH_QUIET_HOURS_ENABLED=#{PushQuietHours.enabled?}"
    puts "  PUSH_QUIET_HOURS_WINDOW=#{PushQuietHours.window_label}"
  end
end

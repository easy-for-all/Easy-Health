require "json"

namespace :make_webhook do
  desc "Check Make webhook configuration status"
  task config: :environment do
    puts "\n=== Make Webhook Configuration ==="
    puts "MAKE_WEBHOOK_ENABLED      : #{ENV.fetch('MAKE_WEBHOOK_ENABLED', '(not set)')}"
    puts "MAKE_WEBHOOK_URL          : #{mask(ENV['MAKE_WEBHOOK_URL'])}"
    puts "MAKE_WEBHOOK_SECRET       : #{mask(ENV['MAKE_WEBHOOK_SECRET'])}"
    puts "MAKE_WEBHOOK_TIMEOUT_SECONDS: #{MakeWebhookEligibility.timeout_seconds}"
    puts "MAKE_WEBHOOK_PAYLOAD_MODE : #{MakeWebhookEligibility.payload_mode}"
    puts "MAKE_WEBHOOK_ALLOWED_EVENTS: #{MakeWebhookEligibility.allowed_events.join(', ').presence || '(none — no events will be sent)'}"
    puts "MAKE_EVENT_SCHEMA_VERSION : #{MakeWebhookEligibility.event_schema_version}"
    puts ""
    puts "configured? => #{MakeWebhookEligibility.configured?}"
    puts ""
  end

  desc "Fire a test event to Make webhook for a user. Usage: rake make_webhook:fire USER=<email|id> EVENT=<event_name>"
  task fire: :environment do
    user   = resolve_user(ENV["USER"])
    event  = ENV["EVENT"].to_s.strip

    abort_task("Missing USER env var. Usage: rake make_webhook:fire USER=<email|id> EVENT=<event_name>") if user.nil?
    abort_task("Missing EVENT env var. Available: #{RelationshipEventTracker::EVENTS.join(', ')}") if event.blank?
    abort_task("Unknown event '#{event}'. Available: #{RelationshipEventTracker::EVENTS.join(', ')}") unless RelationshipEventTracker::EVENTS.include?(event)

    puts "\n=== Make Webhook Fire ==="
    puts "User  : #{user.email} (id=#{user.id})"
    puts "Event : #{event}"
    puts ""

    unless MakeWebhookEligibility.configured?
      puts "ABORT: Make webhook not configured."
      puts "  Set MAKE_WEBHOOK_ENABLED=true, MAKE_WEBHOOK_URL, and MAKE_WEBHOOK_SECRET."
      next
    end

    unless MakeWebhookEligibility.event_allowed?(event)
      puts "ABORT: Event '#{event}' not in MAKE_WEBHOOK_ALLOWED_EVENTS."
      puts "  Current allowed: #{MakeWebhookEligibility.allowed_events.join(', ').presence || '(none)'}"
      next
    end

    unless MakeWebhookEligibility.user_eligible_for_relationship?(user)
      puts "ABORT: User not eligible for relationship delivery (deleted, bounced, no consent, etc)."
      next
    end

    user_event = UserEvent.create!(
      user: user,
      event_name: event,
      occurred_at: Time.current,
      source: "rake_make_webhook_fire",
      metadata: { test: true, triggered_by: "rake" },
      make_delivery_status: "pending"
    )

    puts "UserEvent created: id=#{user_event.id}"
    puts "Delivering synchronously..."
    puts ""

    result = MakeWebhookClient.new.deliver(user_event)

    puts "Result  : #{result.status}"
    puts "Error   : #{result.error}" if result.error.present?
    puts "Success : #{result.success?}"
    puts ""
  end

  desc "Retry all failed Make webhook deliveries (up to MAX_ATTEMPTS)"
  task retry_failed: :environment do
    failed = UserEvent.failed_make_delivery
    puts "\n=== Retrying #{failed.count} failed Make deliveries ==="

    failed.find_each do |user_event|
      print "  UserEvent #{user_event.id} (#{user_event.event_name}) ... "
      result = MakeWebhookClient.new.deliver(user_event)
      puts result.status
    end

    puts ""
  end

  # The ActiveJob adapter is :async (in-process), so every restart or deploy
  # drops whatever retries were queued and leaves those UserEvents sitting in
  # "pending" forever. Nothing re-drives them today. This task is that sweeper,
  # and it carries the "make_pending_retry" heartbeat so its own silence is
  # detectable — see docs/observability/RUNBOOK.md.
  desc "Re-drive Make deliveries stuck in pending (dropped by an in-process queue restart)"
  task retry_pending: :environment do
    Observability::Context.for_task("make_pending_retry") do
      Observability::Heartbeat.track("make_pending_retry") do
        age_minutes = Observability::Config.make_backlog_age_minutes
        limit = Integer(ENV.fetch("LIMIT", "200"), exception: false) || 200

        stuck = UserEvent.pending_make_delivery
                         .where(created_at: ..age_minutes.minutes.ago)
                         .order(:created_at)
                         .limit(limit)

        stats = MakePendingDeliveryRetry.call(scope: stuck, batch: false)

        puts "\n=== Make pending retry ==="
        puts "  older than    : #{age_minutes} min"
        puts "  considered    : #{stats[:considered]}"
        puts "  delivered     : #{stats[:delivered]}"
        puts "  failed        : #{stats[:failed]}"
        puts ""
        stats
      end
    end
  end

  desc "Show recent Make delivery stats"
  task stats: :environment do
    puts "\n=== Make Webhook Delivery Stats ==="
    UserEvent::DELIVERY_STATUSES.each do |status|
      count = UserEvent.where(make_delivery_status: status).count
      puts "  #{status.ljust(22)}: #{count}"
    end

    recent_failed = UserEvent.failed_make_delivery.order(updated_at: :desc).limit(5)
    if recent_failed.any?
      puts "\nLast 5 failures:"
      recent_failed.each do |ue|
        puts "  ##{ue.id} #{ue.event_name} — #{ue.make_last_error}"
      end
    end
    puts ""
  end

  desc "Audit Make delivery data without mutating it. Usage: rake make_webhook:audit [EXPECT_DATA=1] [HOURS=24] [LIMIT=20]"
  task audit: :environment do
    generated_at = Time.current
    hours = make_positive_integer_env("HOURS", 24)
    limit = make_positive_integer_env("LIMIT", 20, max: 100)
    since = generated_at - hours.hours
    expect_data = ActiveModel::Type::Boolean.new.cast(ENV.fetch("EXPECT_DATA", "false"))

    base_counts = {
      users: User.count,
      app_installations: AppInstallation.count,
      device_tokens: DeviceToken.count,
      user_events: UserEvent.count
    }
    empty_database = base_counts.values.all?(&:zero?)

    report = {
      audit: "make_delivery_audit_v3",
      ok: !(expect_data && empty_database),
      result: expect_data && empty_database ? "empty_database" : "ok",
      expect_data: expect_data,
      generated_at: generated_at.iso8601,
      window_hours: hours,
      counts: base_counts.merge(user_events_in_window: UserEvent.where(created_at: since..generated_at).count),
      delivery_statuses: make_group_counts(UserEvent.all, :make_delivery_status, UserEvent::DELIVERY_STATUSES),
      processing_statuses: make_group_counts(UserEvent.all, :make_processing_status, UserEvent::PROCESSING_STATUSES),
      recent_events: make_recent_delivery_events(limit)
    }

    puts JSON.pretty_generate(JSON.parse(JSON.generate(report)))
  end

  def resolve_user(input)
    return nil if input.blank?

    if input.include?("@")
      User.find_by(email: input)
    else
      User.find_by(id: input.to_i)
    end
  end

  def mask(value)
    return "(not set)" if value.blank?
    return value if value.length <= 8

    "#{value[0..3]}...#{value[-4..]}"
  end

  def make_positive_integer_env(key, default, max: nil)
    value = Integer(ENV.fetch(key, default.to_s), exception: false)
    value = default if value.nil? || value <= 0
    max ? [ value, max ].min : value
  end

  def make_group_counts(scope, column, known_values)
    grouped = scope.group(column).count.transform_keys { |key| key.to_s.presence || "(blank)" }
    known_values.index_with { |value| grouped[value].to_i }.merge(grouped.except(*known_values))
  end

  def make_recent_delivery_events(limit)
    UserEvent.order(created_at: :desc).limit(limit).map do |event|
      {
        id: event.id,
        event_name: event.event_name,
        user_id: event.user_id,
        delivery_status: event.make_delivery_status,
        processing_status: event.make_processing_status,
        attempts: event.make_attempts_count,
        http_status: event.make_last_http_status,
        destination: event.make_destination,
        channels: event.make_delivery_channels_list,
        created_at: event.created_at&.iso8601,
        updated_at: event.updated_at&.iso8601
      }.compact
    end
  end

  def abort_task(msg)
    puts "\nERROR: #{msg}\n"
    exit 1 # rubocop:disable Rails/Exit
  end
end

namespace :make do
  desc "Preview a Make event payload without persisting or sending. Usage: bin/rails \"make:preview_event[email,event_name]\" [CHANNELS=email,push]"
  task :preview_event, [:email, :event_name] => :environment do |_task, args|
    user = make_resolve_exact_user!(args[:email])
    event_name = make_validate_event_name!(args[:event_name])
    channels = make_resolve_channels!(event_name, ENV["CHANNELS"])
    metadata = make_synthetic_metadata(user, event_name, persist: false)
    event = make_preview_user_event(user, event_name, metadata)
    payload = Make::EventPayloadSerializer.new(event: event, delivery_channels: channels).as_json

    puts "\n=== Make Event Preview ==="
    puts "User  : #{make_mask_email(user.email)} (id=#{user.id})"
    puts "Event : #{event_name}"
    puts "Schema: #{payload[:schema_version]}"
    puts "Send  : no"
    puts ""
    puts JSON.pretty_generate(JSON.parse(JSON.generate(payload)))
    puts ""
  rescue CommunicationEvents::ConfigError, Make::EventPayloadSerializer::IncompleteEventError, ArgumentError => e
    make_abort(e.message)
  end

  desc "Create and optionally send a test event to Make. Usage: bin/rails \"make:test_event[email,event_name]\" [CHANNELS=email,push] [DRY_RUN=true]"
  task :test_event, [:email, :event_name] => :environment do |_task, args|
    user = make_resolve_exact_user!(args[:email])
    event_name = make_validate_event_name!(args[:event_name])
    channels = make_resolve_channels!(event_name, ENV["CHANNELS"])
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))

    make_guard_production_test! unless dry_run

    metadata = make_synthetic_metadata(user, event_name, persist: !dry_run)
    if dry_run
      event = make_preview_user_event(user, event_name, metadata)
      payload = Make::EventPayloadSerializer.new(event: event, delivery_channels: channels).as_json
    else
      make_abort("Make webhook is not configured") unless MakeWebhookEligibility.configured?
      make_abort("Event '#{event_name}' is not in MAKE_WEBHOOK_ALLOWED_EVENTS") unless MakeWebhookEligibility.event_allowed?(event_name)
      make_abort("User is not eligible for current Make relationship delivery gate") unless MakeWebhookEligibility.user_eligible_for_relationship?(user)

      event = UserEvent.create!(
        user: user,
        event_name: event_name,
        occurred_at: Time.current,
        source: "make_manual_test",
        metadata: metadata,
        make_delivery_status: "pending"
      )
      payload = Make::EventPayloadSerializer.new(event: event, delivery_channels: channels).as_json
      event.update!(payload_json: JSON.parse(JSON.generate(payload)))
    end

    puts "\n=== Make Event Test ==="
    puts "User  : #{make_mask_email(user.email)} (id=#{user.id})"
    puts "Event : #{event_name}"
    puts "Schema: #{payload[:schema_version]}"
    puts "Dry   : #{dry_run}"
    puts "Send  : #{dry_run ? 'no' : 'yes'}"
    puts ""
    puts JSON.pretty_generate(JSON.parse(JSON.generate(payload)))
    puts ""

    next if dry_run

    result = MakeWebhookClient.new.deliver(event, delivery_channels: channels)
    puts "Result : #{result.status}"
    puts "Error  : #{result.error}" if result.error.present?
    puts ""
  rescue CommunicationEvents::ConfigError, Make::EventPayloadSerializer::IncompleteEventError, ArgumentError => e
    make_abort(e.message)
  end

  def make_resolve_exact_user!(email)
    value = email.to_s.strip
    make_abort("Missing email") if value.blank?
    make_abort("Expected an exact email, not a user id") unless value.include?("@")

    User.find_by(email: value).tap do |user|
      make_abort("User not found for #{make_mask_email(value)}") unless user
    end
  end

  def make_validate_event_name!(event_name)
    name = event_name.to_s.strip
    make_abort("Missing event_name") if name.blank?
    make_abort("Unknown event '#{name}'") unless RelationshipEventTracker::EVENTS.include?(name)

    CommunicationEvents.validate_event_name!(name)
  end

  def make_resolve_channels!(event_name, raw_channels)
    return nil if raw_channels.blank?

    channels = CommunicationEvents.validate_channels!(raw_channels.split(","))
    configured = CommunicationEvents.channels_for(event_name)
    unsupported = channels - configured
    make_abort("Channel(s) not configured for #{event_name}: #{unsupported.join(', ')}") if unsupported.any?

    channels
  end

  def make_preview_user_event(user, event_name, metadata)
    UserEvent.new(
      user: user,
      event_name: event_name,
      occurred_at: Time.current,
      source: "make_manual_preview",
      metadata: metadata,
      make_delivery_status: "disabled"
    ).tap { |event| event.id = 0 }
  end

  def make_synthetic_metadata(user, event_name, persist:)
    metadata = {
      test: true,
      trigger_source: "manual_test",
      note: "make webhook smoke test"
    }

    case event_name
    when "workout_created_not_started"
      make_abort("User already has workout sessions; cannot create coherent workout_created_not_started test") if user.workout_sessions.exists?
      plan = make_find_or_create_plan(user, persist: persist)
      metadata.merge!(
        workout_plan_id: plan[:id],
        workout_created_at: plan[:created_at].iso8601
      )
    when "first_workout_created"
      plan = make_find_or_create_plan(user, persist: persist)
      metadata.merge!(
        workout_plan_id: plan[:id],
        workout_created_at: plan[:created_at].iso8601
      )
    when "plan_created_but_not_used"
      make_abort("User already has workout sessions; cannot create coherent plan_created_but_not_used test") if user.workout_sessions.exists?
      plan = make_find_or_create_plan(user, persist: persist)
      metadata.merge!(
        workout_plan_id: plan[:id],
        workout_plan_created_at: plan[:created_at].iso8601
      )
    when "first_workout_completed"
      session = make_find_or_create_completed_session(user, persist: persist)
      metadata.merge!(
        workout_session_id: session[:id],
        workout_day_id: session[:workout_day_id],
        duration_minutes: session[:duration_minutes],
        completion_status: "completed",
        completed_at: session[:completed_at].iso8601
      ).compact!
    when /\Auser_inactive_(3|7|15)_days\z/
      days = Regexp.last_match(1).to_i
      last_workout_at = user.workout_sessions.maximum(:completed_at)
      if last_workout_at && last_workout_at > days.days.ago
        make_abort("User is not inactive for #{days} days; cannot create coherent #{event_name} test")
      end

      session = make_find_or_create_completed_session(user, persist: persist, completed_at: (days + 1).days.ago)
      metadata.merge!(
        last_workout_at: session[:completed_at].iso8601,
        days_since_last_workout: days + 1
      )
    when "never_created_workout"
      make_abort("User already has workout plans; cannot create coherent never_created_workout test") if user.workout_plans.exists?
    end

    metadata
  end

  def make_find_or_create_plan(user, persist:)
    plan = user.workout_plans.order(:created_at).first
    return { id: plan.id, created_at: plan.created_at } if plan
    return { id: 999, created_at: 2.hours.ago } unless persist

    created_at = 2.hours.ago
    plan = user.workout_plans.create!(active: true)
    plan.update_columns(created_at: created_at, updated_at: created_at) # rubocop:disable Rails/SkipsModelValidations
    { id: plan.id, created_at: plan.created_at }
  end

  def make_find_or_create_completed_session(user, persist:, completed_at: 1.day.ago)
    session = user.workout_sessions.where(status: "completed").order(:completed_at).first
    return make_session_hash(session) if session
    return { id: 999, workout_day_id: nil, duration_minutes: 30, completed_at: completed_at } unless persist

    session = user.workout_sessions.create!(
      status: "completed",
      completion_status: "completed",
      completed_at: completed_at,
      duration_minutes: 30
    )
    make_session_hash(session)
  end

  def make_session_hash(session)
    {
      id: session.id,
      workout_day_id: session.workout_day_id,
      duration_minutes: session.duration_minutes,
      completed_at: session.completed_at
    }
  end

  def make_guard_production_test!
    return unless Rails.env.production?
    return if ActiveModel::Type::Boolean.new.cast(ENV.fetch("CONFIRM_PRODUCTION_MAKE_TEST", "false"))

    make_abort("Refusing to send Make test event in production without CONFIRM_PRODUCTION_MAKE_TEST=true")
  end

  def make_mask_email(email)
    local, domain = email.to_s.split("@", 2)
    return "(blank)" if local.blank? || domain.blank?

    "#{local.first}***@#{domain}"
  end

  def make_abort(message)
    puts "\nERROR: #{message}\n"
    exit 1 # rubocop:disable Rails/Exit
  end
end

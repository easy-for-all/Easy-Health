require "json"

# Read-only + smoke-test tooling around the canonical communication contract
# (config/communication_events.yml). These tasks NEVER invent a channel and
# always resolve channels from the canonical config.
namespace :communication_events do
  desc "Audit communication_events.yml. Read-only; exits non-zero if invalid."
  task audit: :environment do
    header = %w[event_name enabled channels communication_type push_notification_type push_route email_template_key status]
    rows = []
    invalid = false

    CommunicationEvents.configured_event_names.each do |name|
      push = CommunicationEvents.push_config_for(name)
      email = CommunicationEvents.email_config_for(name)
      status =
        begin
          CommunicationEvents.assert_entry!(name)
          "valid"
        rescue CommunicationEvents::ConfigError => e
          invalid = true
          "invalid: #{e.message}"
        end

      rows << [
        name,
        CommunicationEvents.enabled?(name).to_s,
        CommunicationEvents.channels_for(name).join("+").presence || "-",
        CommunicationEvents.communication_type_for(name) || "-",
        push&.dig("notification_type") || "-",
        push&.dig("route") || "-",
        email&.dig("template_key") || "-",
        status
      ]
    end

    print_table(header, rows)
    puts ""

    if invalid
      warn "communication_events: INVALID configuration detected"
      exit 1 # rubocop:disable Rails/Exit
    end

    puts "communication_events: all #{rows.size} events valid"
  end

  desc "Preview a communication payload without persisting or sending. Usage: rake \"communication_events:preview[event_name,email]\""
  task :preview, [ :event_name, :email ] => :environment do |_task, args|
    user = ce_resolve_user!(args[:email])
    event_name = ce_validate_event!(args[:event_name])
    event = ce_preview_event(user, event_name)
    payload = Make::EventPayloadSerializer.new(event: event).as_json

    puts "\n=== Communication Event Preview ==="
    puts "User  : #{ce_mask_email(user.email)} (id=#{user.id})"
    puts "Event : #{event_name}"
    puts "Schema: #{payload[:schema_version]}"
    puts "Send  : no"
    puts ""
    puts JSON.pretty_generate(JSON.parse(JSON.generate(payload)))
    puts ""
  rescue CommunicationEvents::ConfigError, Make::EventPayloadSerializer::IncompleteEventError, ArgumentError => e
    ce_abort(e.message)
  end

  desc "Send a controlled smoke-test communication through the canonical pipeline. Usage: rake \"communication_events:deliver[event_name,email]\""
  task :deliver, [ :event_name, :email ] => :environment do |_task, args|
    user = ce_resolve_user!(args[:email])
    event_name = ce_validate_event!(args[:event_name])

    ce_abort("Make webhook is not configured") unless MakeWebhookEligibility.configured?
    ce_abort("Event '#{event_name}' is not in MAKE_WEBHOOK_ALLOWED_EVENTS") unless MakeWebhookEligibility.event_allowed?(event_name)
    ce_abort("Event '#{event_name}' has no communication channels configured") if CommunicationEvents.channels_for(event_name).empty?

    # Manual smoke test: canonical config, unique idempotency key, consent still
    # enforced by the client. No inline allowlist override.
    idempotency_key = "smoke:#{event_name}:#{Time.now.utc.to_i}:#{SecureRandom.hex(4)}"
    event = RelationshipEventTracker.track(
      user: user,
      event_name: event_name,
      metadata: { manual_smoke_test: true },
      source: "manual_communication_test",
      idempotency_key: idempotency_key,
      suppress_make_delivery: true
    )
    ce_abort("Could not create UserEvent for #{event_name}") if event.nil?

    puts "\n=== Communication Event Deliver (manual smoke test) ==="
    puts "User   : #{ce_mask_email(user.email)} (id=#{user.id})"
    puts "Event  : #{event_name} (id=#{event.id})"
    puts "Source : manual_communication_test"
    puts ""

    result = MakeWebhookClient.new.deliver(event)
    puts "Result : #{result.status}"
    puts "Error  : #{result.error}" if result.error.present?
    puts ""
  rescue CommunicationEvents::ConfigError, ArgumentError => e
    ce_abort(e.message)
  end

  def ce_resolve_user!(email)
    value = email.to_s.strip
    ce_abort("Missing email. Usage: rake \"communication_events:preview[event_name,email]\"") if value.blank?
    ce_abort("Expected an exact email, not a user id") unless value.include?("@")

    User.find_by(email: value).tap do |user|
      ce_abort("User not found for #{ce_mask_email(value)}") unless user
    end
  end

  def ce_validate_event!(event_name)
    name = event_name.to_s.strip
    ce_abort("Missing event_name") if name.blank?
    ce_abort("Unknown event '#{name}'") unless CommunicationEvents.known?(name)

    name
  end

  def ce_preview_event(user, event_name)
    UserEvent.new(
      user: user,
      event_name: event_name,
      occurred_at: Time.current,
      source: "manual_communication_test",
      metadata: { manual_smoke_test: true },
      make_delivery_status: "disabled"
    ).tap { |event| event.id = 0 }
  end

  def print_table(header, rows)
    widths = header.each_index.map { |i| ([ header[i] ] + rows.map { |r| r[i].to_s }).map(&:length).max }
    line = ->(cols) { cols.each_index.map { |i| cols[i].to_s.ljust(widths[i]) }.join("  ") }
    puts "\n=== Communication Events Audit ==="
    puts line.call(header)
    puts widths.map { |w| "-" * w }.join("  ")
    rows.each { |row| puts line.call(row) }
  end

  def ce_mask_email(email)
    local, domain = email.to_s.split("@", 2)
    return "(blank)" if local.blank? || domain.blank?

    "#{local.first}***@#{domain}"
  end

  def ce_abort(message)
    puts "\nERROR: #{message}\n"
    exit 1 # rubocop:disable Rails/Exit
  end
end

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

  desc "Show recent Make delivery stats"
  task stats: :environment do
    puts "\n=== Make Webhook Delivery Stats ==="
    UserEvent::DELIVERY_STATUSES.each do |status|
      count = UserEvent.where(make_delivery_status: status).count
      puts "  #{status.ljust(10)}: #{count}"
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

  def abort_task(msg)
    puts "\nERROR: #{msg}\n"
    exit 1 # rubocop:disable Rails/Exit
  end
end

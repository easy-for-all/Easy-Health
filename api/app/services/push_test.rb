require "securerandom"

# Backing logic for the push:test:* rake tasks. Kept as a plain module (not in the
# rake file) so the guards are readable and unit-testable. All output goes to
# stdout; secrets and raw tokens are never printed (tokens are masked).
#
# Safety model:
# - Any task that SENDS or MUTATES resolves the target via resolve_admin!, which
#   aborts unless the email maps to exactly one admin user. Non-admins are never
#   targeted. inspect_user/report are read-only and admin-agnostic.
module PushTest
  # Raised for guard failures; the rake wrapper turns it into `abort`.
  class Abort < StandardError; end

  module_function

  # ---- read-only diagnostics -------------------------------------------------

  def inspect_user(email)
    email = email.to_s.strip
    raise Abort, "Usage: bin/rails \"push:test:inspect_user[EMAIL]\"" if email.blank?

    exact = User.find_by(email: email)
    near = near_matches(email).reject { |u| u.id == exact&.id }

    puts "== push:test:inspect_user =="
    puts "query email: #{email}"

    if exact.nil?
      puts "❌ Exact match: NONE for <#{email}> (nothing was created/renamed)."
      if near.any?
        puts "🔎 Similar records found (diagnostic only — not used):"
        near.each { |u| puts "   - ##{u.id} <#{u.email}> admin=#{u.admin?}" }
        raise Abort, "Multiple/near matches only — resolve the intended email before sending." if near.size > 1
      else
        puts "🔎 No similar records either."
      end
      return
    end

    puts "✅ Exact match found."
    print_user_diagnostic(exact)

    if near.any?
      puts "🔎 Also found similar (NOT used):"
      near.each { |u| puts "   - ##{u.id} <#{u.email}> admin=#{u.admin?}" }
    end
    exact
  end

  def inspect_environment
    puts "== push:test:inspect_environment =="
    puts "Rails.env: #{Rails.env}"
    puts "Time.zone: #{Time.zone.name} (now=#{Time.current.iso8601})"
    puts "ACTIVATION_PUSH_ENABLED: #{PushActivationEligibility.enabled?}"
    puts "ACTIVATION_PUSH_EXPERIMENT_ENABLED: #{PushActivationEligibility.experiment_enabled?}"
    puts "FirebasePushService.configured?: #{FirebasePushService.configured?}"
    puts "Firebase project_id: #{FirebasePushService.project_id || '(none)'}"
    puts "active android device_tokens (all users): #{DeviceToken.active.where(platform: 'android').count}"
    puts "scheduled deliveries due now: #{NotificationDelivery.due.count}"
    puts "NOTE: recurring send depends on external VPS cron running push_activation:* every ~15min."
  end

  def report(email)
    user = User.find_by(email: email.to_s.strip)
    raise Abort, "❌ No user for <#{email}>." if user.nil?

    puts "== push:test:report =="
    print_user_diagnostic(user)

    puts "-- deliveries --"
    NotificationDelivery.where(user_id: user.id).group(:status).count.each do |status, count|
      puts "   #{status}: #{count}"
    end
    last = NotificationDelivery.where(user_id: user.id).order(created_at: :desc).first
    puts "   last: #{last ? "##{last.id} #{last.notification_type} #{last.status} (#{last.created_at.iso8601})" : '-'}"

    puts "-- recent push events --"
    UserEvent.where(user_id: user.id, event_name: PUSH_EVENTS)
             .order(created_at: :desc).limit(10)
             .each { |e| puts "   #{e.created_at.iso8601} #{e.event_name}" }

    puts "-- eligibility --"
    NotificationDelivery::TYPES.each do |type|
      reason = PushActivationEligibility.reason_ineligible(user, notification_type: type)
      puts "   #{type}: #{reason ? "ineligible (#{reason})" : 'eligible'}"
    end
  end

  # ---- mutating / sending (admin-only) --------------------------------------

  def send_now(email)
    user = resolve_admin!(email)
    correlation_id = SecureRandom.uuid
    puts "== push:test:send_now =="
    puts "target: ##{user.id} <#{user.email}> (admin)"
    puts "correlation_id: #{correlation_id}"

    result = AdminPushTestService.new(user).call(correlation_id: correlation_id)
    if result.ok?
      puts "✅ At least one device accepted by FCM (NOT proof of on-device delivery)."
    else
      puts "❌ Not sent (error=#{result.error || 'all_rejected'})."
    end
    Array(result.devices).each do |d|
      puts "   → #{d.masked_token} status=#{d.status} message_id=#{d.message_id || '-'} " \
           "error_code=#{d.error_code || '-'} invalidated=#{d.invalidated}"
    end
    result
  end

  # Creates a reversible, standalone due delivery so the dispatcher/queue can be
  # exercised without waiting for the real preferred-time slot. Prints how to
  # remove it so no inconsistent row is left behind.
  def schedule(email, minutes)
    user = resolve_admin!(email)
    mins = minutes.to_i
    scheduled_for = Time.current + mins.minutes

    delivery = NotificationDelivery.create!(
      user: user,
      notification_type: "first_workout_reminder",
      status: "scheduled",
      scheduled_for: scheduled_for,
      idempotency_key: "push_test:#{user.id}:#{SecureRandom.hex(4)}",
      payload_json: { "test" => true, "scheduled_local_hour" => scheduled_for.in_time_zone.hour }
    )
    puts "== push:test:schedule =="
    puts "created delivery ##{delivery.id} for ##{user.id} <#{user.email}> due #{scheduled_for.iso8601} (+#{mins}min)"
    puts "run:    bin/rails \"push:test:run_dispatcher[#{user.email}]\"  (after due time)"
    puts "remove: bin/rails runner \"NotificationDelivery.find(#{delivery.id}).destroy\"  (cleanup)"
    delivery
  end

  def run_scheduler(email)
    user = resolve_admin!(email)
    puts "== push:test:run_scheduler =="
    puts "target: ##{user.id} <#{user.email}>"
    NotificationDelivery::TYPES.each do |type|
      reason = PushActivationEligibility.reason_ineligible(user, notification_type: type)
      puts "   #{type} eligibility: #{reason || 'eligible'}"
    end
    stats = FirstWorkoutReminderEligibilityJob.perform_now(only_user_ids: [user.id])
    puts "reminder scheduler stats (scoped to user): #{stats.inspect}"
    pending = NotificationDelivery.pending.where(user_id: user.id).order(:scheduled_for)
    puts "pending deliveries: #{pending.map { |d| "##{d.id} #{d.notification_type} @#{d.scheduled_for.iso8601}" }.presence&.join(', ') || 'none'}"
    stats
  end

  def run_dispatcher(email)
    user = resolve_admin!(email)
    due = NotificationDelivery.due.where(user_id: user.id).order(:scheduled_for)
    puts "== push:test:run_dispatcher =="
    puts "target: ##{user.id} <#{user.email}> — due deliveries: #{due.count}"
    if due.empty?
      puts "   nothing due. Use push:test:schedule first or wait for scheduled_for."
      return {}
    end
    stats = Hash.new(0)
    due.find_each do |delivery|
      outcome = PushDispatchService.new(delivery).call
      stats[outcome] += 1
      puts "   → delivery ##{delivery.id} #{delivery.notification_type}: #{outcome} " \
           "(status=#{delivery.reload.status} error=#{delivery.error_code || '-'})"
    end
    puts "dispatcher stats: #{stats.inspect}"
    stats
  end

  # Proves the invalidation path end-to-end on an ISOLATED fake token without
  # touching the user's real tokens. Leaves no fake row behind.
  def invalidate_fake_token(email)
    user = resolve_admin!(email)
    real_before = user.device_tokens.active.count
    fake = user.device_tokens.create!(
      token: "FAKE-INVALID-#{SecureRandom.hex(16)}",
      platform: "android",
      enabled: true,
      permission_status: "granted"
    )
    puts "== push:test:invalidate_fake_token =="
    puts "created isolated fake token #{fake.masked_token} (##{fake.id}) for ##{user.id}"

    if FirebasePushService.configured?
      result = FirebasePushService.new.deliver(token: fake.token, title: "t", body: "t", data: { type: "invalidation_probe" })
      puts "FCM result: status=#{result.status} error_code=#{result.error_code || '-'} invalid_token=#{result.invalid_token}"
      fake.invalidate!(result.error_code || "probe") if result.invalid_token
    else
      puts "⚠️  Firebase not configured — simulating a definitive rejection locally."
      fake.invalidate!("simulated_unregistered")
    end

    fake.reload
    puts "fake token now: enabled=#{fake.enabled?} invalidated_at=#{fake.invalidated_at&.iso8601 || '-'} reason=#{fake.invalidation_reason || '-'}"
    real_after = user.device_tokens.active.where.not(id: fake.id).count
    puts "real active tokens untouched: before=#{real_before} after=#{real_after} (#{real_before == real_after ? 'OK' : 'MISMATCH!'})"
  ensure
    fake&.destroy
    puts "fake token row removed — no residue left."
  end

  # ---- helpers ---------------------------------------------------------------

  PUSH_EVENTS = %w[
    push_scheduled push_sent push_failed push_opened push_deep_link_opened
    push_provider_accepted push_provider_rejected notification_skipped
    admin_push_test_requested notification_disliked notification_type_disabled
  ].freeze

  def resolve_admin!(email)
    email = email.to_s.strip
    raise Abort, "Usage: task[EMAIL]" if email.blank?

    user = User.find_by(email: email)
    raise Abort, "❌ No user for <#{email}> — not creating one. Run push:test:inspect_user first." if user.nil?
    raise Abort, "🚫 Refusing: <#{email}> (##{user.id}) is NOT admin. Test sends target admin only." unless user.admin?

    user
  end

  def near_matches(email)
    local = email.to_s.split("@").first.to_s
    return User.none if local.blank?

    User.where("lower(email) LIKE ?", "%#{local.downcase}%").limit(10).to_a
  end

  def print_user_diagnostic(user)
    prefs = user.notification_preferences
    hp = user.health_profile
    tokens = user.device_tokens.order(created_at: :desc)
    active = tokens.select { |t| t.enabled? && t.invalidated_at.nil? }
    latest = tokens.first

    puts "user: ##{user.id} <#{user.email}>"
    puts "admin: #{user.admin?}"
    puts "time_zone: #{user.time_zone.presence || '(default America/Sao_Paulo)'}"
    puts "preferred_workout_time: #{hp&.preferred_workout_time&.strftime('%H:%M') || '(unset)'}"
    puts "access: has_active_access=#{user.has_active_access?} trial_active=#{user.trial_active?} " \
         "subscription=#{user.subscription&.status || '-'}"
    puts "notification_prefs: push_enabled=#{prefs&.push_enabled?} reminders=#{prefs&.workout_reminders_enabled?} " \
         "opted_out=#{prefs&.notifications_disabled_at.present?} variant=#{prefs&.activation_push_variant || '-'}"
    puts "device_tokens: total=#{tokens.size} active=#{active.size} disabled=#{tokens.size - active.size}"
    tokens.each do |t|
      puts "   - #{t.masked_token} platform=#{t.platform} enabled=#{t.enabled?} " \
           "permission=#{t.permission_status || '-'} app_version=#{t.app_version || '-'} " \
           "last_seen=#{t.last_seen_at&.iso8601 || '-'} " \
           "invalidated=#{t.invalidated_at&.iso8601 || '-'}"
    end
    puts "latest token updated: #{latest&.updated_at&.iso8601 || '-'}"
  end
end

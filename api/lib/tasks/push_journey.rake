# Push journey V1 eligibility sweeps. Run via external cron every ~15min.
# These only EMIT UserEvents (delivered to Make); they never send push directly.
# Inactivity (3d/7d) is emitted by the daily relationship job.
namespace :push_journey do
  desc "Emit first_workout_not_started_2h for users who created a plan 2-26h ago and haven't started"
  task first_workout_not_started_2h: :environment do
    stats = FirstWorkoutNotStarted2hJob.perform_now
    puts "[push_journey:first_workout_not_started_2h] #{stats.inspect}"
  end

  desc "Emit first_workout_not_started_24h for users who created a plan 24-48h ago and haven't started"
  task first_workout_not_started_24h: :environment do
    stats = FirstWorkoutNotStarted24hJob.perform_now
    puts "[push_journey:first_workout_not_started_24h] #{stats.inspect}"
  end

  # Read-only. Answers "why did nothing arrive on the phone?" without sending
  # anything: prints every gate Make::PushDispatchRequest evaluates, in order.
  desc "Diagnose why pushes are being skipped for a user: rake push_journey:diagnose[email]"
  task :diagnose, [ :email ] => :environment do |_t, args|
    user = User.find_by(email: args[:email].to_s.strip.downcase)
    abort("user not found: #{args[:email]}") if user.nil?

    prefs = user.notification_preferences
    puts "user_id=#{user.id} email=#{user.email} admin=#{user.admin?}"
    if prefs.nil?
      puts "notification_preferences: MISSING -> every push skips with global_opt_out"
    else
      puts "push_enabled=#{prefs.push_enabled?} workout_reminders_enabled=#{prefs.workout_reminders_enabled?} " \
           "workout_ready_enabled=#{prefs.workout_ready_enabled?}"
      puts "notifications_disabled_at=#{prefs.notifications_disabled_at.inspect} disabled_reason=#{prefs.disabled_reason.inspect}"
    end

    active = user.device_tokens.active
    puts "device_tokens: total=#{user.device_tokens.count} active=#{active.count} " \
         "deliverable=#{active.where(permission_status: [ nil, 'granted' ]).count}"
    active.each do |t|
      puts "  #{t.masked_token} platform=#{t.platform} permission=#{t.permission_status.inspect} last_seen=#{t.last_seen_at}"
    end

    engagement = PushDispatch.where(user_id: user.id,
                                    notification_type: ::Make::PushDispatchRequest::ENGAGEMENT_CATEGORIES,
                                    status: PushDispatch::DELIVERED_STATUSES)
    last = engagement.where.not(dispatched_at: nil).order(dispatched_at: :desc).first
    in_week = engagement.where("dispatched_at > ?", 7.days.ago).count
    puts "engagement last_delivered=#{last&.dispatched_at.inspect} " \
         "cooldown_active=#{last.present? && last.dispatched_at > 20.hours.ago} " \
         "delivered_last_7d=#{in_week}/#{::Make::PushDispatchRequest::ENGAGEMENT_WEEKLY_CAP}"

    puts "recent dispatches:"
    PushDispatch.where(user_id: user.id).order(id: :desc).limit(15).each do |d|
      puts "  ##{d.id} #{d.created_at.strftime('%d/%m %H:%M')} #{d.notification_type} #{d.campaign_key} " \
           "status=#{d.status} skip_reason=#{d.skip_reason.inspect} error=#{d.last_error_code.inspect}"
    end
  end
end

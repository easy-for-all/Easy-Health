require "json"
require "time"

namespace :scheduled_workout_reminders do
  desc "Run scheduled workout reminder sweep. Optional: USER_ID=123 NOW=2026-07-21T06:30:00-03:00"
  task run: :environment do
    now = scheduled_workout_reminder_parse_now(ENV["NOW"])
    only_user_ids = ENV["USER_ID"].present? ? [ ENV["USER_ID"].to_i ] : nil

    stats = ScheduledWorkoutReminderSchedulerJob.perform_now(now: now, only_user_ids: only_user_ids)
    puts "[scheduled_workout_reminders:run] now=#{now.iso8601} stats=#{stats.inspect}"
  end

  desc "Create a manual scheduled reminder event for an admin user. Usage: bin/rails \"scheduled_workout_reminders:manual_test[email]\""
  task :manual_test, [ :email ] => :environment do |_task, args|
    user = scheduled_workout_reminder_resolve_admin!(args[:email].presence || ENV["EMAIL"].presence || ENV["USER_ID"].presence)
    scheduled_workout_reminder_guard_production_manual_test!

    now = scheduled_workout_reminder_parse_now(ENV["NOW"])
    result = ScheduledWorkoutReminderEligibility.new(
      user: user,
      now: now,
      campaign: ScheduledWorkoutReminderEligibility::MANUAL_CAMPAIGN,
      manual: true
    ).call

    unless result.eligible?
      puts "[scheduled_workout_reminders:manual_test] ineligible #{result.to_h.inspect}"
      next
    end

    event = ScheduledWorkoutReminderEventEmitter.new(
      result: result,
      occurred_at: now,
      source: "manual_test"
    ).call

    payload = Make::EventPayloadSerializer.new(event: event, schema_version: 2).as_json
    puts "[scheduled_workout_reminders:manual_test] event_id=#{event.id} make_delivery_status=#{event.make_delivery_status}"
    puts JSON.pretty_generate(JSON.parse(JSON.generate(payload)))
  end

  def scheduled_workout_reminder_parse_now(value)
    return Time.current if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    parsed = Time.zone.parse(value.to_s)
    abort("Invalid NOW value: #{value}") unless parsed

    parsed
  end

  def scheduled_workout_reminder_resolve_admin!(input)
    value = input.to_s.strip
    abort("Missing admin email or USER_ID") if value.blank?

    user = value.include?("@") ? User.find_by(email: value) : User.find_by(id: value.to_i)
    abort("User not found: #{value}") unless user
    abort("Refusing manual test for non-admin user_id=#{user.id}") unless user.admin?

    user
  end

  def scheduled_workout_reminder_guard_production_manual_test!
    return unless Rails.env.production?
    return if ActiveModel::Type::Boolean.new.cast(ENV.fetch("CONFIRM_PRODUCTION_SCHEDULED_WORKOUT_REMINDER_MANUAL_TEST", "false"))

    abort("Refusing production manual test without CONFIRM_PRODUCTION_SCHEDULED_WORKOUT_REMINDER_MANUAL_TEST=true")
  end
end

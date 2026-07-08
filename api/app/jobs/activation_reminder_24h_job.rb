# Candidates: created a workout plan 24-48h ago, still haven't started a
# workout. Run via an external scheduler (see lib/tasks/activation_reminders.rake) -
# there's no in-repo cron.
class ActivationReminder24hJob < ActivationReminderJob
  private

  def event_name
    "activation_reminder_24h_due"
  end

  def window_range
    48.hours.ago..24.hours.ago
  end
end

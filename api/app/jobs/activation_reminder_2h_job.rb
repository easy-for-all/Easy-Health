# Candidates: created a workout plan 2-26h ago, still haven't started a
# workout. Run via an external scheduler (see lib/tasks/activation_reminders.rake) -
# there's no in-repo cron.
class ActivationReminder2hJob < ActivationReminderJob
  private

  def event_name
    "activation_reminder_2h_due"
  end

  def window_range
    26.hours.ago..2.hours.ago
  end
end

class ClientAdherenceService
  WEEK_DAYS = 7

  def initialize(client)
    @client = client
  end

  def weekly_adherence
    plan = @client.active_workout_plan
    return nil unless plan

    planned_days = plan.workout_days.count
    return nil if planned_days.zero?

    completed = @client.workout_sessions
                       .where("completed_at >= ?", WEEK_DAYS.days.ago)
                       .count

    [(completed.to_f / planned_days * 100).round, 100].min
  end

  def last_session_at
    @client.workout_sessions.maximum(:completed_at)
  end

  def days_without_training
    last = last_session_at
    return nil unless last
    (Time.current - last).to_i / 86_400
  end

  def inactive_alert?
    days = days_without_training
    days.present? && days >= 7
  end

  def needs_new_plan?
    plan = @client.active_workout_plan
    return true unless plan
    false
  end

  def summary
    {
      weekly_adherence: weekly_adherence,
      last_session_at: last_session_at,
      days_without_training: days_without_training,
      inactive_alert: inactive_alert?,
      needs_new_plan: needs_new_plan?
    }
  end
end

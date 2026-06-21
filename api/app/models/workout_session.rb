class WorkoutSession < ApplicationRecord
  belongs_to :user
  belongs_to :workout_day, optional: true

  validates :completed_at, presence: true
  validates :duration_minutes, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :fatigue_level, numericality: { only_integer: true, in: 1..5 }, allow_nil: true

  after_create :maybe_create_community_post
  after_commit :trigger_fitness_recalibration, on: :create

  private

  def trigger_fitness_recalibration
    RecalibrateFitnessProfileJob.perform_later(user_id, source: "workout_completed")
  end

  def maybe_create_community_post
    return unless user.community_enabled?
    return unless user.public_profile&.show_workouts

    streak = recent_streak
    post_type = streak >= 3 ? "streak_achieved" : "workout_completed"
    title = if streak >= 3
      "#{streak} dias seguidos!"
    elsif workout_day&.custom_name.present?
      workout_day.custom_name
    else
      "Treino concluído"
    end

    CommunityPost.create!(
      user: user,
      post_type: post_type,
      title: title,
      metadata: {
        duration_minutes: duration_minutes,
        calories_estimated: calories_estimated,
        streak: streak,
        workout_plan_id: workout_day&.workout_plan_id
      }
    )
  rescue => e
    Rails.logger.warn("[CommunityPost] Failed to create post for session #{id}: #{e.message}")
  end

  def recent_streak
    dates = user.workout_sessions
      .where("completed_at > ?", 30.days.ago)
      .order(completed_at: :desc)
      .pluck(:completed_at)
      .map { |t| t.to_date }
      .uniq

    streak = 0
    last_date = nil
    dates.each do |date|
      if last_date.nil? || last_date - date == 1
        streak += 1
        last_date = date
      else
        break
      end
    end
    streak
  end
end

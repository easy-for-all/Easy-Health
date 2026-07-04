class WorkoutSession < ApplicationRecord
  COMPLETION_STATUSES = %w[completed completed_partial abandoned].freeze
  # Technical lifecycle of the session, orthogonal to completion_status (which
  # describes execution quality). Only "completed" sessions may feed history,
  # last-weight, or progression lookups (see ExerciseHistoryService).
  STATUSES = %w[in_progress completed cancelled].freeze

  belongs_to :user
  belongs_to :workout_day, optional: true
  has_many :exercise_sessions, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :completed_at, presence: true, if: -> { status == "completed" }
  validates :duration_minutes, presence: true, numericality: { only_integer: true, greater_than: 0 }, if: -> { status == "completed" }
  validates :fatigue_level, numericality: { only_integer: true, in: 1..5 }, allow_nil: true
  validates :completion_status, inclusion: { in: COMPLETION_STATUSES }, allow_nil: true
  validates :completion_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  # Guarded by status so the in_progress -> completed transition (finish action)
  # fires these exactly once, and starting a session (in_progress) never does.
  after_create :maybe_create_community_post, if: -> { status == "completed" }
  after_update :maybe_create_community_post, if: -> { saved_change_to_status?(to: "completed") }
  after_commit :trigger_fitness_recalibration, on: :create, if: -> { status == "completed" }
  after_commit :trigger_fitness_recalibration, on: :update, if: -> { saved_change_to_status?(to: "completed") }

  private

  def trigger_fitness_recalibration
    RecalibrateFitnessProfileJob.perform_later(user_id, source: "workout_completed")
  end

  def maybe_create_community_post
    return unless user.community_enabled?

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

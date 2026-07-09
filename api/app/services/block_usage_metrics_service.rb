# Admin metrics about composite training block usage (item 12). Follows the
# same shape as OnboardingAnalyticsService: a plain class, #call returns a
# hash with one key per metric, each backed by a real, already-populated
# data source - no metric here depends on the relational exercise_sessions/
# exercise_sets tables, since those aren't written by the web app today
# (everything the web client logs goes through workout_sessions.exercise_logs
# jsonb instead - see ExerciseHistoryService for the same distinction).
class BlockUsageMetricsService
  def call
    {
      block_type_distribution: block_type_distribution,
      plans_with_composite_blocks_pct: plans_with_composite_blocks_pct,
      users_who_trained_composite_block: users_who_trained_composite_block,
      completion_rate_by_block_type: completion_rate_by_block_type
    }
  end

  private

  def block_type_distribution
    WorkoutBlock.group(:block_type).count
  end

  def plans_with_composite_blocks_pct
    total = WorkoutPlan.active.count
    return 0.0 if total.zero?

    with_composite = WorkoutPlan.active
      .joins(workout_days: :workout_blocks)
      .where(workout_blocks: { block_type: WorkoutBlock::MULTI_EXERCISE_TYPES })
      .distinct
      .count

    ((with_composite.to_f / total) * 100).round(1)
  end

  def users_who_trained_composite_block
    ActiveRecord::Base.connection.execute(<<~SQL.squish).count
      SELECT DISTINCT workout_sessions.user_id
      FROM workout_sessions, jsonb_array_elements(exercise_logs) AS elem
      WHERE (elem->>'block_type') = ANY(ARRAY[#{quoted_multi_exercise_types}])
    SQL
  end

  def completion_rate_by_block_type
    rows = ActiveRecord::Base.connection.execute(<<~SQL.squish)
      SELECT block_type, status, COUNT(DISTINCT session_id) AS session_count
      FROM (
        SELECT DISTINCT
          workout_sessions.id AS session_id,
          workout_sessions.status AS status,
          elem->>'block_type' AS block_type
        FROM workout_sessions, jsonb_array_elements(exercise_logs) AS elem
        WHERE (elem->>'block_type') = ANY(ARRAY[#{quoted_multi_exercise_types}])
      ) sessions_by_block_type
      GROUP BY block_type, status
    SQL

    totals = Hash.new { |h, k| h[k] = { completed: 0, total: 0 } }
    rows.each do |row|
      entry = totals[row["block_type"]]
      count = row["session_count"].to_i
      entry[:total] += count
      entry[:completed] += count if row["status"] == "completed"
    end

    totals.transform_values do |v|
      v[:total].zero? ? 0.0 : ((v[:completed].to_f / v[:total]) * 100).round(1)
    end
  end

  def quoted_multi_exercise_types
    WorkoutBlock::MULTI_EXERCISE_TYPES.map { |t| ActiveRecord::Base.connection.quote(t) }.join(",")
  end
end

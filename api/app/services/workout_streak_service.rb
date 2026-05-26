class WorkoutStreakService
  def initialize(sessions)
    @sessions = sessions
  end

  def current_streak
    return 0 if @sessions.empty?

    dates = sorted_dates
    streak = 0
    expected = Date.today

    dates.each do |date|
      break if date < expected - 1

      streak += 1
      expected = date - 1
    end

    streak
  end

  def best_streak
    return 0 if @sessions.empty?

    dates = sorted_dates
    best = 1
    current = 1

    dates.each_cons(2) do |a, b|
      if a - b == 1
        current += 1
        best = [best, current].max
      else
        current = 1
      end
    end

    best
  end

  def last_activity_at
    @sessions.first&.completed_at&.to_date
  end

  private

  def sorted_dates
    @sorted_dates ||= @sessions
      .map { |s| s.completed_at.to_date }
      .uniq
      .sort
      .reverse
  end
end

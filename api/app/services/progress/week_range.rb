module Progress
  class WeekRange
    # Returns a Range from Sunday to Saturday of the current week (user's timezone).
    def self.current
      today = Time.zone.today
      start_of_week = today - today.wday.days   # Sunday (wday=0 → no change, wday=1 → -1, etc.)
      end_of_week   = start_of_week + 6.days    # Saturday
      start_of_week..end_of_week
    end
  end
end

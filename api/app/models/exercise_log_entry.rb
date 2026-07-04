# Normalizes a single legacy exercise_logs (JSONB) entry so every reader
# (ExerciseHistoryService fallback, personal records, volume, etc.) parses
# weight_by_set/reps/is_warmup_by_set the same way instead of duplicating it.
class ExerciseLogEntry
  attr_reader :raw, :completed_at

  def initialize(raw, completed_at: nil)
    @raw = raw || {}
    @completed_at = completed_at
  end

  def exercise_id
    raw["exercise_id"]
  end

  def name
    raw["name"]
  end

  def weight_by_set
    @weight_by_set ||= Array(raw["weight_by_set"]).map { |w| w.to_s.presence && w.to_f }
  end

  def reps_by_set
    @reps_by_set ||= begin
      value = raw["reps"]
      if value.is_a?(Array)
        value.map { |r| r.to_s.presence && r.to_i }
      else
        Array.new(weight_by_set.size, value.to_s.presence && value.to_i)
      end
    end
  end

  def warmup_by_set
    @warmup_by_set ||= Array(raw["is_warmup_by_set"])
  end

  def warmup?(index)
    !!warmup_by_set[index]
  end

  def working_weights
    weight_by_set.each_index.filter_map { |i| weight_by_set[i] if weight_by_set[i].to_f > 0 && !warmup?(i) }
  end

  def any_positive_weights
    weight_by_set.compact.select { |w| w.to_f > 0 }
  end

  # Priority: last working (non-warmup) set > last set of any kind > flat weight_kg fallback.
  def last_used_weight
    working_weights.last || any_positive_weights.last || (raw["weight_kg"].to_f > 0 ? raw["weight_kg"].to_f : nil)
  end

  def max_working_weight
    working_weights.max
  end

  def total_reps
    reps_by_set.compact.sum
  end

  def completed_sets_count
    reps_by_set.compact.count { |r| r.to_i > 0 }
  end

  def total_volume_kg
    weight_by_set.each_index.sum do |i|
      next 0 if warmup?(i)

      (weight_by_set[i] || 0) * (reps_by_set[i] || 0)
    end
  end

  def feeling
    raw["feeling"]
  end

  def planned_sets
    raw["planned_sets"]
  end

  def duration_minutes
    raw["duration_minutes"]
  end

  def elapsed_seconds
    raw["elapsed_seconds"]
  end

  def intensity
    raw["intensity"]
  end
end

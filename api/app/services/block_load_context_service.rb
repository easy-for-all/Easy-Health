# Applies a conservative fatigue discount to a suggested working weight when
# the exercise is performed inside a multi-exercise block instead of in
# isolation. Sits on top of ExerciseHistoryService/LoadProgressionService's
# suggestion rather than changing their core heuristic.
class BlockLoadContextService
  FACTORS = {
    "single" => 1.0,
    "superset" => 0.90,
    "bi_set" => 0.90,
    "tri_set" => 0.85,
    "circuit" => 0.775 # midpoint of the requested 70-85% range
  }.freeze

  def self.adjust(base_weight, block_type)
    return base_weight if base_weight.blank?

    round_to_supported_increment(base_weight.to_f * FACTORS.fetch(block_type, 1.0))
  end

  def self.reason_suffix(block_type)
    factor = FACTORS.fetch(block_type, 1.0)
    return nil if factor == 1.0

    "Ajustado para bloco: #{block_type} (~#{(factor * 100).round}% da carga isolada)"
  end

  def self.round_to_supported_increment(value)
    step = if value >= 60
      5.0
    elsif value >= 20
      2.5
    else
      1.0
    end
    rounded = (value / step).round * step
    rounded % 1 == 0 ? rounded.to_i : rounded.round(1)
  end
end

# Shared shape of the block-related fields attached to every serialized
# WorkoutDayExercise. Extracted so workout_plans_controller, quick_workouts_controller
# and workout_day_exercises_controller (the three places that already duplicate
# the exercise JSON shape) don't each grow a fourth copy of it.
module WorkoutBlockSerialization
  extend ActiveSupport::Concern

  def block_fields_for(wde)
    block = wde.workout_block
    {
      block_type: block&.block_type || "single",
      block_id: wde.workout_block_id,
      block_position: block&.position,
      position_in_block: wde.position_in_block || 0,
      block_rounds: block&.rounds || 1,
      block_rest_between_rounds_seconds: block&.rest_between_rounds_seconds,
      block_label: block&.label,
      target_reps_min: wde.target_reps_min,
      target_reps_max: wde.target_reps_max,
      tempo: wde.tempo,
      rir: wde.rir,
      rpe: wde.rpe,
      is_optional: wde.is_optional,
      notes: wde.notes
    }
  end
end

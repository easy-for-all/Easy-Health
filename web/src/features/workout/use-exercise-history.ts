import type { WorkoutDayExercise } from "@/shared/types/workout";

/**
 * Reads history fields the backend already computed via ExerciseHistoryService
 * (last_execution_label, last_weight_kg, suggested_weight_kg, progression_reason).
 * The frontend must never recompute these by scanning a local sessions list -
 * that client-side scanning (bounded to a 7-day window, unaware of in-progress
 * or cancelled sessions) was the root cause of "done today" showing up for the
 * exercise the user was still executing.
 */
export function exerciseHasHistory(exercise: WorkoutDayExercise): boolean {
  return !!exercise.last_execution_label && exercise.last_execution_label !== "Primeira vez neste exercício";
}

/** Weight to pre-fill a set with: last real weight used, falling back to the planned weight. */
export function historyWeight(exercise: WorkoutDayExercise): string | undefined {
  const weight = exercise.last_weight_kg ?? exercise.planned_weight_kg;
  return weight != null && Number(weight) > 0 ? String(weight) : undefined;
}

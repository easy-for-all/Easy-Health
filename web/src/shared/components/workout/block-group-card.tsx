"use client";

import type { ReactNode } from "react";
import type { WorkoutDayExercise } from "@/shared/types/workout";
import {
  isMultiExerciseBlock,
  blockConnectorLabel,
  type WorkoutBlockGroup,
} from "@/features/workout/workout-blocks";

/**
 * Shared visual grouping for a block of exercises (superset/bi_set/tri_set/
 * circuit), used by both the pre-workout list (PlanDayDetailDrawer) and the
 * today/OverviewScreen list, so the "these exercises go together" chrome
 * isn't implemented a third time.
 *
 * Deliberately does NOT own the per-exercise card markup (image, sets/reps
 * inputs, swap/delete buttons) - the two screens already render fairly
 * different card content for those, so `renderExercise` stays a render prop.
 * A "single" block (or any block with exactly one exercise) renders exactly
 * like today: no wrapper, no connector badge.
 */
export function BlockGroupCard({
  group,
  renderExercise,
}: {
  group: WorkoutBlockGroup;
  // isGrouped tells the caller whether this exercise lives inside a visible
  // multi-exercise wrapper - used to suppress the per-exercise up/down move
  // controls, since moving one exercise alone would break the block.
  renderExercise: (exercise: WorkoutDayExercise, indexInBlock: number, isGrouped: boolean) => ReactNode;
}) {
  const isGrouped = isMultiExerciseBlock(group.blockType) && group.exercises.length > 1;

  if (!isGrouped) {
    return <>{group.exercises.map((exercise, idx) => renderExercise(exercise, idx, false))}</>;
  }

  const connectors = group.exercises.map((_, idx) => blockConnectorLabel(idx)).join(" + ");

  return (
    <div className="space-y-3 rounded-xl border-2 border-primary-200 bg-primary-50/40 p-3 dark:border-primary-900 dark:bg-primary-950/20">
      <div>
        <p className="text-sm font-bold text-primary-700 dark:text-primary-300">
          {group.blockLabel} · {group.rounds} {group.rounds === 1 ? "rodada" : "rodadas"}
        </p>
        {group.rationale && (
          <p className="mt-0.5 text-xs text-primary-500 dark:text-primary-400">{group.rationale}</p>
        )}
      </div>

      <div className="space-y-3">
        {group.exercises.map((exercise, idx) => (
          <div key={exercise.workout_day_exercise_id} className="relative pl-2">
            <span className="absolute -left-1 -top-1 z-10 flex h-6 w-6 items-center justify-center rounded-full bg-primary-500 text-[11px] font-bold text-white shadow">
              {blockConnectorLabel(idx)}
            </span>
            {renderExercise(exercise, idx, true)}
          </div>
        ))}
      </div>

      <p className="text-xs font-medium text-primary-600 dark:text-primary-400">
        {group.restBetweenRoundsSeconds != null
          ? `Descanso: ${group.restBetweenRoundsSeconds}s após completar ${connectors}`
          : "Sem descanso entre exercícios do bloco — apenas após a rodada completa"}
      </p>
    </div>
  );
}

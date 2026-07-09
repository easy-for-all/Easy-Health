/* ============================================================
   EasyHealth — agrupamento de blocos de treino compostos
   Fonte ÚNICA de verdade para transformar o array plano
   `day.exercises` (order_index) em grupos visuais/de execução
   (single, superset, bi_set, tri_set, circuit, ...).
   ============================================================ */

import type { WorkoutDayExercise } from "@/shared/types/workout";

export interface WorkoutBlockGroup {
  blockId: number | null;
  blockType: string;
  blockLabel: string;
  rounds: number;
  restBetweenRoundsSeconds: number | null;
  exercises: WorkoutDayExercise[]; // already ordered by position_in_block
}

const MULTI_EXERCISE_TYPES = new Set(["superset", "bi_set", "tri_set", "circuit"]);

const BLOCK_TYPE_LABELS: Record<string, string> = {
  superset: "Superset",
  bi_set: "Bi-set",
  tri_set: "Tri-set",
  circuit: "Circuito",
  warmup: "Aquecimento",
  strength_block: "Bloco de força",
  hypertrophy_block: "Bloco de hipertrofia",
  cardio_block: "Bloco de cardio",
  mobility_block: "Bloco de mobilidade",
  finisher: "Finisher",
  cooldown: "Desaquecimento",
};

export function isMultiExerciseBlock(blockType: string | undefined | null): boolean {
  return MULTI_EXERCISE_TYPES.has(blockType ?? "single");
}

/**
 * Groups the flat, order_index-ordered `exercises` array into visual/
 * execution blocks. Exercises missing `block_id`/`block_type` (data cached
 * before this feature shipped, or synthesized quick-workout items) are
 * treated as their own isolated "single" block - never grouped with
 * neighbors - so older sessionStorage state and quick workouts keep working
 * without any migration.
 */
export function groupExercisesIntoBlocks(exercises: WorkoutDayExercise[]): WorkoutBlockGroup[] {
  const groups: WorkoutBlockGroup[] = [];
  const groupIndexByKey = new Map<string, number>();
  const labelCounts: Record<string, number> = {};

  exercises.forEach((exercise, idx) => {
    const blockType = exercise.block_type ?? "single";
    const key = exercise.block_id != null ? `id:${exercise.block_id}` : `idx:${idx}`;

    let groupIndex = groupIndexByKey.get(key);
    if (groupIndex === undefined) {
      groupIndex = groups.length;
      groupIndexByKey.set(key, groupIndex);

      labelCounts[blockType] = (labelCounts[blockType] ?? 0) + 1;
      const baseLabel = BLOCK_TYPE_LABELS[blockType] ?? "Bloco";
      const blockLabel = blockType === "single" ? "" : `${baseLabel} ${labelCounts[blockType]}`;

      groups.push({
        blockId: exercise.block_id ?? null,
        blockType,
        blockLabel,
        rounds: exercise.block_rounds ?? 1,
        restBetweenRoundsSeconds: exercise.block_rest_between_rounds_seconds ?? null,
        exercises: [],
      });
    }

    groups[groupIndex].exercises.push(exercise);
  });

  // Defensive: keep block-internal order tied to position_in_block rather
  // than array insertion order, in case the flat array ever arrives
  // out-of-order relative to it (e.g. stale cached state).
  groups.forEach((group) => {
    group.exercises.sort((a, b) => (a.position_in_block ?? 0) - (b.position_in_block ?? 0));
  });

  return groups;
}

// "A1", "A2"... - the block's own label ("Superset 1", "Circuito 2") already
// disambiguates which block this is, so the connector letter is always "A".
export function blockConnectorLabel(index: number): string {
  return `A${index + 1}`;
}

export type BlockStep =
  | { type: "next_exercise_in_round"; positionInBlock: number }
  | { type: "rest_before_next_round"; restSeconds: number; nextRound: number }
  | { type: "block_complete" };

/**
 * Decides what happens after the current exercise's set/round is marked
 * done, for an exercise living inside a multi-exercise block. Only meant to
 * be consulted when `isMultiExerciseBlock(group.blockType)` is true - single
 * blocks keep the pre-existing per-exercise flow untouched.
 *
 * "1 round = 1 set" for exercises inside a composite block: there is no
 * separate round counter in exerciseRuntime, `currentRound` doubles as the
 * set index already tracked today.
 */
export function nextStepInBlock(
  group: WorkoutBlockGroup,
  positionInBlock: number,
  currentRound: number,
  fallbackRestSeconds: number
): BlockStep {
  const hasNextExerciseInRound = positionInBlock + 1 < group.exercises.length;
  if (hasNextExerciseInRound) {
    return { type: "next_exercise_in_round", positionInBlock: positionInBlock + 1 };
  }

  if (currentRound < group.rounds) {
    return {
      type: "rest_before_next_round",
      restSeconds: group.restBetweenRoundsSeconds ?? fallbackRestSeconds,
      nextRound: currentRound + 1,
    };
  }

  return { type: "block_complete" };
}

// Block types the manual "add block" wizard can produce. bi_set/tri_set
// still exist in the backend enum (WorkoutBlock::BLOCK_TYPES) for data
// created elsewhere, but the wizard only offers these two, mirroring
// WorkoutDayExercisesController#block_exercise_count_valid?.
export type WizardBlockType = "superset" | "circuit";

export function minExercisesForBlockType(blockType: WizardBlockType): number {
  return blockType === "superset" ? 2 : 3;
}

export function isValidBlockSize(blockType: WizardBlockType, count: number): boolean {
  return blockType === "superset" ? count === 2 : count >= minExercisesForBlockType(blockType);
}

import {
  groupExercisesIntoBlocks,
  isMultiExerciseBlock,
  blockConnectorLabel,
  nextStepInBlock,
  isValidBlockSize,
  minExercisesForBlockType,
} from "@/features/workout/workout-blocks";
import type { WorkoutDayExercise } from "@/shared/types/workout";

function makeExercise(overrides: Partial<WorkoutDayExercise>): WorkoutDayExercise {
  return {
    workout_day_exercise_id: 1,
    exercise_id: 1,
    name: "Exercício",
    muscle_group: "chest",
    exercise_type: "musculacao",
    description: "",
    image_url: "",
    muscle_image_url: "",
    sets: 3,
    reps: 10,
    rest_seconds: 60,
    order_index: 0,
    ...overrides,
  };
}

describe("isMultiExerciseBlock", () => {
  it("is true for superset, bi_set, tri_set and circuit", () => {
    expect(isMultiExerciseBlock("superset")).toBe(true);
    expect(isMultiExerciseBlock("bi_set")).toBe(true);
    expect(isMultiExerciseBlock("tri_set")).toBe(true);
    expect(isMultiExerciseBlock("circuit")).toBe(true);
  });

  it("is false for single and other block types", () => {
    expect(isMultiExerciseBlock("single")).toBe(false);
    expect(isMultiExerciseBlock("warmup")).toBe(false);
    expect(isMultiExerciseBlock(undefined)).toBe(false);
    expect(isMultiExerciseBlock(null)).toBe(false);
  });
});

describe("groupExercisesIntoBlocks", () => {
  it("treats each single-block exercise as its own isolated group", () => {
    const exercises = [
      makeExercise({ workout_day_exercise_id: 1, block_type: "single", block_id: 10, order_index: 0 }),
      makeExercise({ workout_day_exercise_id: 2, block_type: "single", block_id: 11, order_index: 1 }),
    ];

    const groups = groupExercisesIntoBlocks(exercises);

    expect(groups).toHaveLength(2);
    expect(groups[0].exercises).toHaveLength(1);
    expect(groups[1].exercises).toHaveLength(1);
  });

  it("groups exercises sharing the same block_id into one superset group, in position_in_block order", () => {
    const exercises = [
      makeExercise({
        workout_day_exercise_id: 1, name: "Supino Inclinado", block_type: "superset",
        block_id: 7, position_in_block: 0, block_rounds: 3, block_rest_between_rounds_seconds: 90, order_index: 0,
      }),
      makeExercise({
        workout_day_exercise_id: 2, name: "Remada Baixa", block_type: "superset",
        block_id: 7, position_in_block: 1, block_rounds: 3, block_rest_between_rounds_seconds: 90, order_index: 1,
      }),
    ];

    const groups = groupExercisesIntoBlocks(exercises);

    expect(groups).toHaveLength(1);
    expect(groups[0].blockType).toBe("superset");
    expect(groups[0].blockLabel).toBe("Superset 1");
    expect(groups[0].rounds).toBe(3);
    expect(groups[0].restBetweenRoundsSeconds).toBe(90);
    expect(groups[0].exercises.map((e) => e.name)).toEqual(["Supino Inclinado", "Remada Baixa"]);
  });

  it("numbers repeated block types across the day (Superset 1, Superset 2)", () => {
    const exercises = [
      makeExercise({ workout_day_exercise_id: 1, block_type: "superset", block_id: 1, position_in_block: 0, order_index: 0 }),
      makeExercise({ workout_day_exercise_id: 2, block_type: "superset", block_id: 1, position_in_block: 1, order_index: 1 }),
      makeExercise({ workout_day_exercise_id: 3, block_type: "superset", block_id: 2, position_in_block: 0, order_index: 2 }),
      makeExercise({ workout_day_exercise_id: 4, block_type: "superset", block_id: 2, position_in_block: 1, order_index: 3 }),
    ];

    const groups = groupExercisesIntoBlocks(exercises);

    expect(groups.map((g) => g.blockLabel)).toEqual(["Superset 1", "Superset 2"]);
  });

  it("falls back to one group per exercise when block_type/block_id are missing (pre-feature cached data)", () => {
    const exercises = [
      makeExercise({ workout_day_exercise_id: 1, order_index: 0 }),
      makeExercise({ workout_day_exercise_id: 2, order_index: 1 }),
    ];

    const groups = groupExercisesIntoBlocks(exercises);

    expect(groups).toHaveLength(2);
    expect(groups[0].blockType).toBe("single");
    expect(groups[1].blockType).toBe("single");
  });

  it("preserves block order matching first appearance in the flat array", () => {
    const exercises = [
      makeExercise({ workout_day_exercise_id: 1, block_type: "single", block_id: 1, order_index: 0 }),
      makeExercise({ workout_day_exercise_id: 2, block_type: "circuit", block_id: 2, position_in_block: 0, order_index: 1 }),
      makeExercise({ workout_day_exercise_id: 3, block_type: "circuit", block_id: 2, position_in_block: 1, order_index: 2 }),
    ];

    const groups = groupExercisesIntoBlocks(exercises);

    expect(groups.map((g) => g.blockType)).toEqual(["single", "circuit"]);
  });
});

describe("blockConnectorLabel", () => {
  it("always uses letter A, disambiguated by the block's own label", () => {
    expect(blockConnectorLabel(0)).toBe("A1");
    expect(blockConnectorLabel(1)).toBe("A2");
    expect(blockConnectorLabel(2)).toBe("A3");
  });
});

describe("nextStepInBlock", () => {
  const superset = groupExercisesIntoBlocks([
    makeExercise({
      workout_day_exercise_id: 1, name: "A1", block_type: "superset",
      block_id: 7, position_in_block: 0, block_rounds: 3, block_rest_between_rounds_seconds: 90, order_index: 0,
    }),
    makeExercise({
      workout_day_exercise_id: 2, name: "A2", block_type: "superset",
      block_id: 7, position_in_block: 1, block_rounds: 3, block_rest_between_rounds_seconds: 90, order_index: 1,
    }),
  ])[0];

  it("advances A1 -> A2 within the same round without resting", () => {
    const step = nextStepInBlock(superset, 0, 1, 60);
    expect(step).toEqual({ type: "next_exercise_in_round", positionInBlock: 1 });
  });

  it("rests before the next round after the last exercise of the round, when more rounds remain", () => {
    const step = nextStepInBlock(superset, 1, 1, 60);
    expect(step).toEqual({ type: "rest_before_next_round", restSeconds: 90, nextRound: 2 });
  });

  it("falls back to the given rest seconds when the block has no explicit rest_between_rounds", () => {
    const noRest = { ...superset, restBetweenRoundsSeconds: null };
    const step = nextStepInBlock(noRest, 1, 1, 45);
    expect(step).toEqual({ type: "rest_before_next_round", restSeconds: 45, nextRound: 2 });
  });

  it("signals block_complete after the last exercise of the last round", () => {
    const step = nextStepInBlock(superset, 1, 3, 60);
    expect(step).toEqual({ type: "block_complete" });
  });

  it("runs a circuit through all exercises before resting, same as a superset", () => {
    const circuit = groupExercisesIntoBlocks([
      makeExercise({ workout_day_exercise_id: 1, block_type: "circuit", block_id: 9, position_in_block: 0, block_rounds: 2, order_index: 0 }),
      makeExercise({ workout_day_exercise_id: 2, block_type: "circuit", block_id: 9, position_in_block: 1, block_rounds: 2, order_index: 1 }),
      makeExercise({ workout_day_exercise_id: 3, block_type: "circuit", block_id: 9, position_in_block: 2, block_rounds: 2, order_index: 2 }),
    ])[0];

    expect(nextStepInBlock(circuit, 0, 1, 60)).toEqual({ type: "next_exercise_in_round", positionInBlock: 1 });
    expect(nextStepInBlock(circuit, 1, 1, 60)).toEqual({ type: "next_exercise_in_round", positionInBlock: 2 });
    expect(nextStepInBlock(circuit, 2, 1, 60)).toEqual({ type: "rest_before_next_round", restSeconds: 60, nextRound: 2 });
    expect(nextStepInBlock(circuit, 2, 2, 60)).toEqual({ type: "block_complete" });
  });
});

describe("minExercisesForBlockType / isValidBlockSize", () => {
  it("requires exactly 2 exercises for a superset", () => {
    expect(minExercisesForBlockType("superset")).toBe(2);
    expect(isValidBlockSize("superset", 1)).toBe(false);
    expect(isValidBlockSize("superset", 2)).toBe(true);
    expect(isValidBlockSize("superset", 3)).toBe(false);
  });

  it("requires 3 or more exercises for a circuit", () => {
    expect(minExercisesForBlockType("circuit")).toBe(3);
    expect(isValidBlockSize("circuit", 2)).toBe(false);
    expect(isValidBlockSize("circuit", 3)).toBe(true);
    expect(isValidBlockSize("circuit", 5)).toBe(true);
  });
});

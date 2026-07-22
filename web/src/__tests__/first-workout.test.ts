import { describe, expect, it } from "vitest";
import { hasCompletedWorkout, workoutStartCopy } from "@/features/workout/first-workout";

describe("first workout copy", () => {
  it("uses completed workout fields instead of the legacy timestamp", () => {
    expect(hasCompletedWorkout({ has_completed_workout: true, completed_workouts_count: 0 })).toBe(true);
    expect(hasCompletedWorkout({ has_completed_workout: false, completed_workouts_count: 2 })).toBe(true);
    expect(hasCompletedWorkout({ has_completed_workout: false, completed_workouts_count: 0 })).toBe(false);
  });

  it("does not show beginner copy while the user is unavailable", () => {
    expect(workoutStartCopy(null)).toBe("▶ Iniciar treino");
    expect(workoutStartCopy(undefined)).toBe("▶ Iniciar treino");
  });

  it("switches between first workout and returning user copy", () => {
    expect(workoutStartCopy({ has_completed_workout: false, completed_workouts_count: 0 })).toBe(
      "▶ Fazer meu primeiro treino",
    );
    expect(workoutStartCopy({ has_completed_workout: true, completed_workouts_count: 1 })).toBe("▶ Iniciar treino");
  });
});

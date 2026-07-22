import type { User } from "@/shared/types/user";

type WorkoutCompletionUser = Pick<User, "completed_workouts_count" | "has_completed_workout"> | null | undefined;

export function hasCompletedWorkout(user: WorkoutCompletionUser): boolean {
  return user?.has_completed_workout === true || (user?.completed_workouts_count ?? 0) > 0;
}

export function workoutStartCopy(user: WorkoutCompletionUser): string {
  return user && !hasCompletedWorkout(user) ? "▶ Fazer meu primeiro treino" : "▶ Iniciar treino";
}

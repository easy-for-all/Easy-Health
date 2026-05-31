export type FitnessLevel = "beginner" | "intermediate" | "advanced";
export type Goal = "lose_weight" | "gain_muscle" | "maintain" | "health";
export type ActivityType =
  | "musculacao" | "cardio"    | "natacao"
  | "corrida"    | "funcional" | "caminhada" | "hiit";
export type Gender = "male" | "female" | "not_informed";

export interface HealthProfile {
  id: number;
  age: number;
  weight_kg: number;
  height_cm: number;
  fitness_level: FitnessLevel;
  goal: Goal;
  activity_preferences: ActivityType[];
  training_days_per_week?: number;
  gender?: Gender | null;
}

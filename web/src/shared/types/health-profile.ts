export type FitnessLevel = "beginner" | "intermediate" | "advanced";
export type Goal =
  | "lose_weight" | "gain_muscle" | "maintain" | "health"
  | "body_definition" | "conditioning" | "strength" | "mobility"
  | "safe_return" | "health_longevity";
export type ActivityType =
  | "musculacao" | "cardio"    | "natacao"
  | "corrida"    | "funcional" | "caminhada" | "hiit";
export type Gender = "male" | "female" | "not_informed";
export type TrainingLocation = "full_gym" | "simple_gym" | "home" | "condo" | "outdoor" | "hotel_travel" | "unknown";
export type BodyFocus = "full_body" | "glutes" | "legs" | "abs" | "arms" | "chest" | "back" | "shoulders" | "mobility_posture" | "conditioning_cardio";
export type TrainingStyle = "traditional_strength" | "short_sessions" | "cardio" | "functional" | "calisthenics" | "mobility" | "mixed" | "unknown";
export type Equipment = "machine" | "dumbbell" | "barbell" | "plates" | "resistance_band" | "treadmill" | "stationary_bike" | "rower" | "jump_rope" | "bodyweight" | "none";
export type IntensityPreference = "easy_start" | "balanced" | "intense" | "progressive" | "unknown";
export type TrainingContext = "none" | "postpartum" | "pregnant" | "menstrual_cycle_impact" | "prefer_not_to_say";

export interface ExercisePreference {
  id: number;
  name: string;
  muscle_group: string | null;
}

export interface HealthProfile {
  id: number;
  age: number;
  weight_kg: number;
  height_cm: number;
  fitness_level: FitnessLevel;
  goal: Goal;
  activity_preferences: ActivityType[];
  training_days_per_week?: number;
  training_location?: TrainingLocation;
  gender?: Gender | null;
  limitations?: string[];
  preferred_body_focus?: BodyFocus[];
  preferred_training_styles?: TrainingStyle[];
  available_equipment?: Equipment[];
  avoided_exercise_ids?: number[];
  session_duration_minutes?: 15 | 25 | 35 | 45 | 60 | null;
  intensity_preference?: IntensityPreference | null;
  training_context?: TrainingContext | null;
  favorite_exercise_ids?: number[];
  favorite_exercises?: ExercisePreference[];
  avoided_exercises?: ExercisePreference[];
}

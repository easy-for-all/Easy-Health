export interface WorkoutDayExercise {
  workout_day_exercise_id: number;
  exercise_id: number;
  name: string;
  muscle_group: string | null;
  exercise_type: string;
  description: string;
  instructions?: string | null;
  image_url: string;
  gif_url?: string | null;
  video_url?: string | null;
  muscle_image_url: string;
  sets: number;
  reps: number;
  rest_seconds: number;
  duration_minutes?: number | null;
  intensity?: string | null;
  order_index: number;
  last_performed_at?: string | null;
}

export interface WorkoutDay {
  id: number | null;
  position?: number;
  day_of_week?: number;
  name: string;
  custom_name?: string | null;
  favorited?: boolean;
  muscle_groups?: string[];
  exercise_types?: string[];
  exercise_count?: number;
  last_completed_at?: string | null;
  exercises?: WorkoutDayExercise[];
  quick?: boolean;
  invalid_workout_reason?: string | null;
}

export interface WorkoutPlan {
  id: number;
  active: boolean;
  created_at?: string | null;
  days: WorkoutDay[];
  ai_rationale?: string | null;
  ai_training_method?: string | null;
  personalization_reason?: string | null;
  user_explanation?: string | null;
  coach_notes?: string | null;
  strategy?: {
    version: string;
    training_split: string;
    primary_focus: string[];
    user_facing_explanation: string;
  } | null;
}

export interface WorkoutSession {
  id: number;
  workout_day_id: number;
  workout_day_name: string;
  completed_at: string;
  duration_minutes: number;
  fatigue_level?: number | null;
  exercise_logs?: {
    workout_day_exercise_id: number;
    exercise_id: number;
    name: string;
    muscle_group?: string | null;
    weight_kg: number | null;
    weight_by_set?: Array<number | null>;
    planned_sets?: number;
    sets: number;
    reps: number | number[];
    rest_seconds?: number;
    feeling?: string | null;
  }[];
  notes: string | null;
  calories_estimated?: number | null;
}

export interface CardioExerciseLog {
  workout_day_exercise_id: number;
  exercise_id: number;
  name: string;
  duration_minutes: number | null;
  intensity: string | null;
  feeling?: string | null;
}

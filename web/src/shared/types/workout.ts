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
  order_index: number;
  last_performed_at?: string | null;
}

export interface WorkoutDay {
  id: number;
  position?: number;
  day_of_week: number;
  name: string;
  muscle_groups?: string[];
  exercise_types?: string[];
  exercise_count?: number;
  exercises?: WorkoutDayExercise[];
}

export interface WorkoutPlan {
  id: number;
  active: boolean;
  days: WorkoutDay[];
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
    weight_kg: number | null;
    weight_by_set?: Array<number | null>;
    planned_sets?: number;
    sets: number;
    reps: number | number[];
    rest_seconds?: number;
    feeling?: string | null;
  }[];
  notes: string | null;
}

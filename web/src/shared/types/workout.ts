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
  planned_weight_kg?: number | string | null;
  rest_seconds: number;
  duration_minutes?: number | null;
  intensity?: string | null;
  order_index: number;
  last_performed_at?: string | null;
  // Server-computed history, from ExerciseHistoryService - the frontend must
  // not recompute any of these by scanning sessions client-side (that was
  // the root cause of "last time" showing up mid-execution).
  last_execution_label?: string;
  last_completed_at?: string | null;
  last_weight_kg?: number | string | null;
  suggested_weight_kg?: number | string | null;
  progression_reason?: string | null;
  // Composite training block context - "single" when the exercise isn't
  // part of a superset/circuit. Absent entirely on data predating this
  // feature (e.g. cached sessionStorage), always treated as "single" then.
  block_type?: string;
  block_id?: number | null;
  block_position?: number | null;
  position_in_block?: number;
  block_rounds?: number;
  block_rest_between_rounds_seconds?: number | null;
  // Short rationale set by WorkoutIntelligence::BlockPlanner when the block
  // was created automatically by the generator (e.g. "Superset para
  // otimizar hipertrofia: ..."). Absent for single blocks and for blocks
  // created manually via the add-block wizard.
  block_label?: string | null;
  target_reps_min?: number | null;
  target_reps_max?: number | null;
  tempo?: string | null;
  rir?: number | null;
  rpe?: number | null;
  is_optional?: boolean;
  notes?: string | null;
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
    is_warmup_by_set?: boolean[];
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

// Snapshot returned by GET /api/v1/workout_sessions/:id - used to restore an
// in-progress session from the server instead of trusting sessionStorage alone.
export interface WorkoutExecutionExerciseSnapshot {
  current_exercise_session_id: number;
  workout_day_exercise_id: number | null;
  exercise_id: number;
  status: "in_progress" | "completed" | "skipped";
  current_set_number: number;
  current_weight_kg: number | string | null;
  completed_sets_count: number;
  total_sets_count: number | null;
  total_volume_kg: number;
}

export interface WorkoutExecutionSnapshot {
  id: number;
  status: "in_progress" | "completed" | "cancelled";
  current_session_id: number;
  is_current_session_in_progress: boolean;
  exercise_sessions: WorkoutExecutionExerciseSnapshot[];
}

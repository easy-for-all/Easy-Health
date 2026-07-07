export type OnboardingFlowKey = "quick" | "complete" | "photo_ai" | "chat_ai";

export type PeriodFilter = "today" | "7d" | "30d" | "";
export type FlowFilter = OnboardingFlowKey | "";
export type StatusFilter = "trial_active" | "trial_expired" | "premium" | "";

export interface FlowSelectionEntry {
  label: string;
  count: number;
  pct: number;
}

export interface ConversionByFlowRow {
  label: string;
  selected: number;
  created_workout: number;
  executed_first: number;
  plus2_sessions: number;
  plus3_sessions: number;
  subscribed: number;
  conversion_to_workout_pct: number;
  conversion_to_subscription_pct: number;
}

export interface TimeToPlanEntry {
  label: string;
  count: number;
  avg_seconds?: number;
  median_seconds?: number;
  p75_seconds?: number;
  avg_label?: string;
  median_label?: string;
}

export interface StepDropoffEntry {
  step_name: string;
  label: string;
  arrived: number;
  completed: number;
  dropoff_pct: number;
  cumulative_pct: number;
}

export interface ActivationByFlowEntry {
  label: string;
  activated_24h: number;
  activated_24h_pct: number;
}

export interface FirstWorkout24h {
  overall: {
    signup_to_first_workout_24h: number;
    signup_to_first_workout_24h_pct: number;
    plan_to_first_workout_24h: number;
    plan_to_first_workout_24h_pct: number;
    avg_time_label: string | null;
    median_time_label: string | null;
  };
  by_flow: Record<string, ActivationByFlowEntry>;
}

export interface ProgressiveProfilingQuestion {
  question_key: string;
  label: string;
  shown: number;
  answered: number;
  skipped: number;
  answer_rate_pct: number;
  top_answer: string | null;
}

export interface ProgressiveProfiling {
  summary: {
    shown: number;
    answered: number;
    skipped: number;
    answer_rate_pct: number;
    skip_rate_pct: number;
  };
  by_question: ProgressiveProfilingQuestion[];
}

export interface AiQualityRow {
  label: string;
  summaries_generated: number;
  summaries_edited: number;
  plans_accepted: number;
  plans_regenerated: number;
  plans_abandoned: number;
  acceptance_pct: number;
  edit_pct: number;
  regeneration_pct: number;
  abandonment_pct: number;
}

export interface PreferenceEntry {
  key: string;
  label: string;
  count: number;
  pct: number;
}

export interface DeclaredPreferences {
  goals: PreferenceEntry[];
  locations: PreferenceEntry[];
  durations: PreferenceEntry[];
  frequencies: PreferenceEntry[];
  limitations: PreferenceEntry[];
  training_preference: {
    intensity: PreferenceEntry[];
    style: PreferenceEntry[];
  };
}

export interface OnboardingAnalytics {
  flow_selection: {
    total: number;
    by_flow: Record<string, FlowSelectionEntry>;
  };
  conversion_by_flow: Record<string, ConversionByFlowRow>;
  time_to_first_plan: Record<string, TimeToPlanEntry>;
  step_dropoff: Record<string, StepDropoffEntry[]>;
  first_workout_24h: FirstWorkout24h;
  progressive_profiling: ProgressiveProfiling;
  ai_quality: Record<string, AiQualityRow>;
  declared_preferences: DeclaredPreferences;
}

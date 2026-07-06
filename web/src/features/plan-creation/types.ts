import type {
  BodyFocus,
  Equipment,
  ExercisePreference,
  FitnessLevel,
  Gender,
  Goal,
  HealthProfile,
  IntensityPreference,
  TrainingContext,
  TrainingLocation,
  TrainingStyle,
} from "@/shared/types/health-profile";

export type EntryMode = "onboarding" | "replan";
export type CreationMode = "quick" | "complete";
// "photo" | "chat" ficam reservados para uma entrega futura — ver create-start.tsx

export type Duration = 15 | 25 | 35 | 45 | 60;
export type Modality = "musculacao" | "cardio" | "misto" | "funcional" | "ai_choice";
export type SplitType = "ai_choice" | "full_body" | "upper_lower" | "ab" | "abc" | "ppl" | "custom";
export type CardioType = "corrida" | "caminhada" | "bicicleta" | "eliptico" | "escada" | "remo" | "hiit" | "natacao" | "ai_choice";
export type CardioFormat = "continuo_leve" | "continuo_moderado" | "intervalado" | "hiit" | "progressivo" | "recuperacao" | "ai_choice";

export type StepId =
  | "create-start"
  | "quick-goal" | "quick-profile" | "quick-place" | "quick-time" | "quick-limits"
  | "complete-goal" | "complete-profile" | "complete-method" | "complete-place"
  | "complete-focus" | "complete-schedule" | "complete-care"
  | "generating" | "error";

export interface WizardFormState {
  goal: Goal | "";
  fitness_level: FitnessLevel | "";
  age: string;
  weight_kg: string;
  height_cm: string;
  gender: Gender | "";
  training_context: TrainingContext | "";
  training_location: TrainingLocation | "";
  available_equipment: Equipment[];
  preferred_body_focus: BodyFocus[];
  preferred_training_styles: TrainingStyle[];
  session_duration_minutes: Duration | null;
  training_days_per_week: number | null;
  intensity_preference: IntensityPreference | "";
  favorite_exercises: ExercisePreference[];
  avoided_exercises: ExercisePreference[];
  limitations: string[];
  modality: Modality;
  split_type: SplitType;
  cardio_type: CardioType;
  cardio_format: CardioFormat;
  custom_splits: { name: string; muscle_groups: string[] }[];
}

export function buildInitialForm(): WizardFormState {
  return {
    goal: "", fitness_level: "", age: "30", weight_kg: "75", height_cm: "175", gender: "",
    training_context: "", training_location: "", available_equipment: [],
    preferred_body_focus: [], preferred_training_styles: [],
    session_duration_minutes: 25, training_days_per_week: 3, intensity_preference: "",
    favorite_exercises: [], avoided_exercises: [], limitations: [],
    modality: "ai_choice", split_type: "ai_choice", cardio_type: "ai_choice", cardio_format: "ai_choice",
    custom_splits: [],
  };
}

// Pré-preenche o form com o profile existente (replan) — evita perguntar de novo o que o
// backend já sabe. Modalidade/split/cardio ficam de fora: GET /health_profile não os retorna
// (ver Api::V1::HealthProfilesController#profile_json), então o modo Completo sempre pergunta
// modalidade do zero, com default "ai_choice".
export function hydrateFormFromProfile(profile: HealthProfile | null): WizardFormState {
  const base = buildInitialForm();
  if (!profile) return base;
  return {
    ...base,
    goal: profile.goal ?? "",
    fitness_level: profile.fitness_level ?? "",
    age: profile.age != null ? String(profile.age) : base.age,
    weight_kg: profile.weight_kg != null ? String(profile.weight_kg) : base.weight_kg,
    height_cm: profile.height_cm != null ? String(profile.height_cm) : base.height_cm,
    gender: profile.gender ?? "",
    training_context: profile.training_context ?? "",
    training_location: profile.training_location ?? "",
    available_equipment: profile.available_equipment ?? [],
    preferred_body_focus: profile.preferred_body_focus ?? [],
    preferred_training_styles: profile.preferred_training_styles ?? [],
    session_duration_minutes: profile.session_duration_minutes ?? null,
    training_days_per_week: profile.training_days_per_week ?? null,
    intensity_preference: profile.intensity_preference ?? "",
    favorite_exercises: profile.favorite_exercises ?? [],
    avoided_exercises: profile.avoided_exercises ?? [],
    limitations: profile.limitations ?? [],
  };
}

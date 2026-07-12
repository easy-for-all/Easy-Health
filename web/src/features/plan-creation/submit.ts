import { ApiError, api } from "@/shared/lib/api";
import type { HealthProfile } from "@/shared/types/health-profile";
import type { WorkoutPlan } from "@/shared/types/workout";
import type { EntryMode, WizardFormState } from "./types";

function buildProfilePayload(form: WizardFormState) {
  return {
    goal: form.goal || undefined,
    fitness_level: form.fitness_level || undefined,
    age: form.age ? Number(form.age) : undefined,
    weight_kg: form.weight_kg ? Number(form.weight_kg) : undefined,
    height_cm: form.height_cm ? Number(form.height_cm) : undefined,
    gender: form.gender || null,
    preferred_body_focus: form.preferred_body_focus,
    preferred_training_styles: form.preferred_training_styles,
    training_location: form.training_location || undefined,
    available_equipment: form.available_equipment,
    session_duration_minutes: form.session_duration_minutes,
    training_days_per_week: form.training_days_per_week ?? undefined,
    intensity_preference: form.intensity_preference || null,
    favorite_exercise_ids: form.favorite_exercises.map((exercise) => exercise.id),
    avoided_exercise_ids: form.avoided_exercises.map((exercise) => exercise.id),
    limitations: form.limitations,
    training_context: form.gender === "female" ? (form.training_context || null) : null,
    // Activation push: when the user usually trains + real IANA timezone. Empty
    // period is omitted so we don't overwrite a previous choice on replan.
    preferred_workout_period: form.preferred_workout_period || undefined,
    preferred_workout_time: form.preferred_workout_period && form.preferred_workout_period !== "variable"
      ? (form.preferred_workout_time || undefined)
      : undefined,
    workout_time_source: form.preferred_workout_period ? "onboarding" : undefined,
    time_zone: resolveTimeZone(),
  };
}

// Real device/browser IANA timezone (e.g. "America/Sao_Paulo"), never an offset.
function resolveTimeZone(): string | undefined {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || undefined;
  } catch {
    return undefined;
  }
}

// Onboarding faz POST (cria o profile); se o profile já existir (422), cai para PATCH —
// mesmo tratamento que já existia em onboarding/page.tsx. Replan sempre faz PATCH direto,
// já que o profile é pré-condição para chegar nesse fluxo.
export async function upsertProfile(entryMode: EntryMode, form: WizardFormState): Promise<HealthProfile> {
  const payload = buildProfilePayload(form);
  // Timeout maior que o default (15s): recalculo de FitnessIntelligence e webhooks
  // síncronos no backend podem levar a resposta bem além do default nesse endpoint.
  const options = { timeout: 30_000 };
  if (entryMode === "replan") {
    return api.patch<HealthProfile>("/api/v1/health_profile", payload, options);
  }
  try {
    return await api.post<HealthProfile>("/api/v1/health_profile", payload, options);
  } catch (err) {
    if (err instanceof ApiError && err.status === 422) {
      return api.patch<HealthProfile>("/api/v1/health_profile", payload, options);
    }
    throw err;
  }
}

// Normaliza sub-tipos de cardio para os únicos ActivityType válidos no backend, preservando
// cardio_type (usado pelo gerador para detalhes do treino). Mesma lógica de
// plan/page.tsx:toActivityPref.
function toActivityPref(cardioType: WizardFormState["cardio_type"]): string {
  const map: Partial<Record<WizardFormState["cardio_type"], string>> = {
    corrida: "corrida", caminhada: "caminhada", natacao: "natacao", hiit: "hiit",
  };
  return map[cardioType] ?? "cardio";
}

export async function generatePlan(form: WizardFormState): Promise<WorkoutPlan & { summary?: string }> {
  const body: Record<string, unknown> = {
    training_days_per_week: form.training_days_per_week ?? 3,
    modality: form.modality,
  };
  if (form.training_location) body.training_location = form.training_location;

  if (form.modality !== "ai_choice") {
    body.split_type = form.split_type;
  }
  if (form.modality === "cardio" || form.modality === "misto") {
    body.cardio_type = form.cardio_type;
    body.cardio_format = form.cardio_format;
  }
  if (form.split_type === "custom" && form.custom_splits.length > 0) {
    body.custom_splits = form.custom_splits;
  }

  if (form.modality === "funcional")  body.activity_preferences = ["funcional"];
  if (form.modality === "cardio")     body.activity_preferences = [toActivityPref(form.cardio_type)];
  if (form.modality === "misto")      body.activity_preferences = ["musculacao", toActivityPref(form.cardio_type)];
  if (form.modality === "musculacao") body.activity_preferences = ["musculacao"];
  // ai_choice: omit activity_preferences so the backend uses its own logic

  return api.post<WorkoutPlan & { summary?: string }>("/api/v1/workout_plan/regenerate", body, { timeout: 90_000 });
}

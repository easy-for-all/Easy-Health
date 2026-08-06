import type { WorkoutPlan, WorkoutDay } from "@/shared/types/workout";
import { anonGet, anonPost, anonPut, GENERATION_TIMEOUT_MS } from "./anon-api";
import { ensureAnonymousSession } from "./anonymous-session";

// Leituras e escritas do plano anônimo.
//
// Os PAYLOADS não moram aqui: eles são construídos em plan-creation/submit.ts,
// que é o único lugar que sabe traduzir o formulário do wizard (modalidade,
// split, activity_preferences derivadas do cardio) para o corpo da requisição.
// Duplicar essa tradução faria os dois fluxos divergirem no primeiro campo novo
// — e a divergência apareceria como "o plano anônimo saiu diferente".

export interface AnonymousState {
  plans_remaining: number;
  plans_generated_count: number;
  max_plans: number;
  has_active_plan: boolean;
  has_profile_answers: boolean;
}

export type AnonymousPlan = WorkoutPlan & { plans_remaining?: number; summary?: string };

// Não há sessão anônima possível: Web/PWA, modo desligado no servidor, build
// antigo ou instalação já vinculada. Quem chama trata como "só dá com conta".
export class AnonymousUnavailableError extends Error {
  constructor() {
    super("anonymous_mode_unavailable");
    this.name = "AnonymousUnavailableError";
  }
}

async function token(): Promise<string> {
  const value = await ensureAnonymousSession();
  if (!value) throw new AnonymousUnavailableError();
  return value;
}

export async function fetchAnonymousState(): Promise<AnonymousState> {
  return anonGet<AnonymousState>(await token(), "/state");
}

export async function saveAnonymousProfile(payload: Record<string, unknown>): Promise<void> {
  await anonPut(await token(), "/profile", payload);
}

export async function generateAnonymousPlan(payload: Record<string, unknown>): Promise<AnonymousPlan> {
  return anonPost<AnonymousPlan>(await token(), "/workout_plan/generate", payload, GENERATION_TIMEOUT_MS);
}

export async function fetchAnonymousPlan(): Promise<AnonymousPlan> {
  return anonGet<AnonymousPlan>(await token(), "/workout_plan");
}

export async function fetchAnonymousToday(): Promise<{ day: WorkoutDay | null }> {
  return anonGet<{ day: WorkoutDay | null }>(await token(), "/workout_plan/today");
}

export async function fetchAnonymousDay(id: number): Promise<{ day: WorkoutDay }> {
  return anonGet<{ day: WorkoutDay }>(await token(), `/workout_days/${id}`);
}

export interface AnonymousSessionPayload {
  workout_day_id?: number | null;
  duration_minutes: number;
  completion_status?: string;
  completion_rate?: number;
  completed_sets_count?: number;
  planned_sets_count?: number;
  source?: string;
  exercise_logs?: unknown[];
}

export async function recordAnonymousSession(payload: AnonymousSessionPayload): Promise<{ id: number }> {
  return anonPost<{ id: number }>(await token(), "/workout_sessions", payload);
}

/* ============================================================
   EasyHealth — classificador de ENGINE de treino
   Fonte ÚNICA de verdade para decidir COMO uma modalidade
   deve ser executada e renderizada.
   ============================================================ */

export type WorkoutEngine = "strength" | "cardio" | "interval" | "recovery";

/* ── Mapeamento por exercise_type ──────────────────────────── */

// Cardio contínuo: foco em tempo / ritmo / distância. SEM séries/reps/peso.
const CARDIO_TYPES = new Set<string>([
  "cardio", "corrida", "caminhada", "bike", "ciclismo",
  "natacao", "eliptico", "remo", "escada",
]);

// Intervalado: ciclos de trabalho/descanso. SEM séries/reps/peso de musculação.
const INTERVAL_TYPES = new Set<string>([
  "hiit", "funcional", "crossfit", "circuito", "spinning", "tabata",
]);

// Recuperação / isometria: tempo-alvo + respiração. SEM peso/reps.
const RECOVERY_TYPES = new Set<string>([
  "mobilidade", "alongamento", "flexibilidade", "yoga", "pilates",
  "isometria", "timed",
]);

// Força: musculação tradicional (séries · reps · carga · descanso).
const STRENGTH_TYPES = new Set<string>([
  "musculacao", "forca", "strength", "calistenia",
]);

/**
 * Decide o engine de um exercício/modalidade.
 * Prioridade: tipo explícito de recuperação/intervalo/cardio  >
 *             presença de grupo muscular (força)              >
 *             fallback por heurística.
 */
export function workoutEngine(ex: {
  exercise_type?: string | null;
  muscle_group?: string | null;
}): WorkoutEngine {
  const t = (ex.exercise_type ?? "").toLowerCase().trim();

  if (RECOVERY_TYPES.has(t)) return "recovery";
  if (INTERVAL_TYPES.has(t)) return "interval";
  if (CARDIO_TYPES.has(t)) return "cardio";
  if (STRENGTH_TYPES.has(t)) return "strength";

  // Heurística de segurança para tipos não mapeados:
  // se tem grupo muscular, trata como força; senão, como cardio
  // (melhor cair no cronômetro do que mostrar séries/kg indevidos).
  return ex.muscle_group ? "strength" : "cardio";
}

/* ── Helpers de conveniência (espelham o uso atual da tela) ── */

// Usa a tela de TEMPO (cronômetro grande, intensidade) — sem séries/reps/peso.
export function usesTimerScreen(ex: { exercise_type?: string | null; muscle_group?: string | null }): boolean {
  const e = workoutEngine(ex);
  return e === "cardio" || e === "interval";
}

// Usa a tela de TEMPO-ALVO (anel + respiração) — mobilidade/alongamento/isometria.
export function usesRecoveryScreen(ex: { exercise_type?: string | null; muscle_group?: string | null }): boolean {
  return workoutEngine(ex) === "recovery";
}

// Usa a tela de FORÇA (séries · reps · carga · descanso).
export function usesStrengthScreen(ex: { exercise_type?: string | null; muscle_group?: string | null }): boolean {
  return workoutEngine(ex) === "strength";
}

/* Rótulo PT-BR do engine (para badges/telas) */
export const ENGINE_LABEL: Record<WorkoutEngine, string> = {
  strength: "Força",
  cardio: "Cardio",
  interval: "Intervalado",
  recovery: "Recuperação",
};

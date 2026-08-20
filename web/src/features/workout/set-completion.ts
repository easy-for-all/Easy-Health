// A parte pura de handleSetDone (/workout/today): dado o runtime do exercício e
// a série atual, o que os arrays viram depois de concluir a série e se havia
// peso informado no momento.
//
// Existe extraída porque a página tem 3400 linhas, 3 contexts e ~15 endpoints —
// um teste que a renderizasse provaria mocks, não comportamento. Aqui a regra de
// propagação de carga e a ausência de peso são verificáveis diretamente.
//
// O tipo do parâmetro é estrutural de propósito: ExerciseRuntime continua
// morando na página, e este módulo não precisa saber do resto dela.

export type SetCompletionState = {
  planned_sets: number;
  reps_by_set: number[];
  weight_by_set: string[];
  warmup_by_set?: boolean[];
};

/** Como o exercício é executado — decide o que conta como progresso. */
export type ExerciseKind = "strength" | "cardio" | "timed";

/** O runtime lido para decidir se um exercício foi executado. */
export type ExerciseProgressState = SetCompletionState & {
  duration_minutes?: number;
  elapsed_seconds?: number;
};

/**
 * Séries com evidência de execução: reps registradas OU peso registrado.
 * Uma das duas basta — desde que o peso deixou de ser obrigatório, uma série
 * legítima pode ter só reps.
 */
export function completedSetCount(state: SetCompletionState): number {
  return state.reps_by_set.filter(
    (reps, i) => reps > 0 || Number(state.weight_by_set[i]) > 0,
  ).length;
}

/**
 * "Este exercício foi executado?" — a MESMA regra que decide `skipped_exercises`
 * no payload enviado ao backend. Definição única de propósito: quando ela vivia
 * duplicada, `workout_exercise_completed` e a sessão salva podiam discordar
 * sobre o mesmo exercício.
 */
export function hasExerciseProgress(kind: ExerciseKind, state: ExerciseProgressState): boolean {
  if (kind === "timed") return (state.elapsed_seconds ?? 0) > 0;
  if (kind === "cardio") return (state.duration_minutes ?? 0) > 0;
  return completedSetCount(state) > 0;
}

export type SetCompletionResult = {
  repsBySet: number[];
  weightBySet: string[];
  /**
   * O usuário tinha um valor de peso preenchido no runtime no momento da
   * conclusão. NÃO é "o peso é diferente de zero" — é a distinção entre informado
   * e não informado, que peso ausente e peso 0 tornariam ambígua no evento.
   */
  hasWeight: boolean;
  /** Peso numérico para os eventos. 0 quando não informado — ver hasWeight. */
  currentWeightNumber: number;
};

/**
 * Peso não é obrigatório para concluir uma série. Ausência é propagada como
 * ausência (string vazia, que o payload converte em null): nunca 0, nunca um
 * valor inventado.
 */
export function buildSetCompletion(
  state: SetCompletionState,
  currentSet: number,
  exerciseReps: number,
): SetCompletionResult {
  const currentWeight = state.weight_by_set[currentSet - 1] ?? "";
  const hasWeight = currentWeight !== "";

  const repsBySet = [...state.reps_by_set];
  repsBySet[currentSet - 1] ||= exerciseReps;

  const weightBySet = [...state.weight_by_set];
  if (currentSet < state.planned_sets && !weightBySet[currentSet]) {
    const isCurrentWarmup = state.warmup_by_set?.[currentSet - 1] ?? false;
    if (!isCurrentWarmup) {
      weightBySet[currentSet] = currentWeight;
    } else {
      // warmup: restore last non-warmup weight so the next normal set is not contaminated
      const lastNormalWeight = state.weight_by_set
        .filter((_, i) => !(state.warmup_by_set?.[i]))
        .filter(Boolean)
        .at(-1);
      weightBySet[currentSet] = lastNormalWeight ?? "";
    }
  }

  return {
    repsBySet,
    weightBySet,
    hasWeight,
    currentWeightNumber: Number(currentWeight) || 0,
  };
}

/**
 * Identidade de uma série dentro da sessão. Usada como guarda de reentrância:
 * dois toques no mesmo frame chegam com a mesma chave, e a série seguinte sempre
 * tem chave diferente — então nenhum toque legítimo é bloqueado.
 */
export function setCompletionKey(workoutDayExerciseId: number, currentSet: number): string {
  return `${workoutDayExerciseId}:${currentSet}`;
}

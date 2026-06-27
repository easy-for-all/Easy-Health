export interface WorkoutContext {
  currentExercise: { id: number; name: string; muscleGroup: string | null };
  exerciseIndex: number;
  totalExercises: number;
  currentSet: number;
  totalSets: number;
  setsRemaining: number;
  exercisesRemaining: number;
  previousExercise: { name: string } | null;
  nextExercise: { name: string } | null;
  weightUsed: number | null;
  repsPlanned: number | null;
  elapsedMinutes: number;
  estimatedMinutesLeft: number;
  isLastSet: boolean;
  isLastExercise: boolean;
  completionPct: number;
  isWarmup: boolean;
}

export function buildRestMessage(ctx: WorkoutContext): string {
  const {
    currentExercise, currentSet, totalSets, isLastSet, isLastExercise,
    weightUsed, exercisesRemaining, setsRemaining, nextExercise, isWarmup,
    completionPct, estimatedMinutesLeft,
  } = ctx;

  if (!isValidContext(ctx)) return safeMessage();

  if (isWarmup) return "Aquecimento concluído. Inicie a carga principal com técnica.";

  if (isLastExercise && isLastSet) {
    return `Última série de ${currentExercise.name}. Foque em manter a execução limpa.`;
  }

  if (isLastSet && nextExercise) {
    return `${currentExercise.name} concluído. Agora vamos para ${nextExercise.name}.`;
  }

  if (isLastSet) {
    return "Última série deste exercício. Foco total.";
  }

  if (currentSet === totalSets - 1 && nextExercise) {
    return `Falta uma série. Depois passamos para ${nextExercise.name}.`;
  }

  if (currentSet === 1 && weightUsed && weightUsed > 0) {
    return `Primeira série com ${weightUsed}kg concluída. Mantenha o controle.`;
  }

  if (setsRemaining > 0 && estimatedMinutesLeft > 0) {
    return `Faltam ${setsRemaining} série${setsRemaining > 1 ? "s" : ""}. Restam cerca de ${estimatedMinutesLeft} min.`;
  }

  if (exercisesRemaining > 0 && setsRemaining > 0) {
    return `Faltam ${exercisesRemaining} exercício${exercisesRemaining > 1 ? "s" : ""} e ${setsRemaining} série${setsRemaining > 1 ? "s" : ""}.`;
  }

  if (completionPct >= 50) return "Você passou da metade. Continue firme.";

  if (isLastExercise) return "Treino quase concluído. Mantenha a intensidade até o fim.";

  return safeMessage();
}

export function validateMessage(message: string, ctx: WorkoutContext): boolean {
  if (!ctx.nextExercise) return true;

  const nextName = ctx.nextExercise.name.toLowerCase();

  if (!ctx.isLastSet && !ctx.isLastExercise) {
    if (message.toLowerCase().includes(nextName)) return false;
  }

  if (ctx.previousExercise) {
    const prevName = ctx.previousExercise.name.toLowerCase();
    const currentName = ctx.currentExercise.name.toLowerCase();
    if (message.toLowerCase().includes(prevName) && !message.toLowerCase().includes(currentName)) {
      return false;
    }
  }

  return true;
}

function isValidContext(ctx: WorkoutContext): boolean {
  return (
    !!ctx.currentExercise?.name &&
    ctx.currentSet > 0 &&
    ctx.totalSets > 0 &&
    ctx.currentSet <= ctx.totalSets + 1
  );
}

function safeMessage(): string {
  const pool = [
    "Respire. Daqui a pouco voltamos.",
    "Recuperando energia...",
    "Prepare-se para a próxima série.",
    "Descanso iniciado. Mantenha o foco.",
    "Próxima série em instantes.",
  ];
  return pool[Math.floor(Math.random() * pool.length)];
}

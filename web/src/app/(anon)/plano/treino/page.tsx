"use client";

import { Suspense, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { ExerciseInfoModal } from "@/shared/components/workout/exercise-info-modal";
import { trackEvent } from "@/shared/lib/analytics";
import { fetchAnonymousDay, fetchAnonymousToday, recordAnonymousSession } from "@/features/anonymous/anonymous-plan";
import type { WorkoutDay, WorkoutDayExercise } from "@/shared/types/workout";
import "@/shared/components/workout/workout-ui.css";

// A execução anônima é o LAÇO CENTRAL e nada mais: listar, marcar série,
// finalizar.
//
// /workout/today tem 3400 linhas e ~15 endpoints autenticados (swap, adicionar,
// remover, reordenar, favoritar, coach, PRs, histórico, sugestão de carga).
// Duplicá-la seria insustentável e refatorá-la em fonte-de-dados arriscaria o
// caminho pago. E o que ela mostra a mais — última carga, peso sugerido, razão
// da progressão, streak — é TUDO derivado de histórico da conta: para um
// anônimo renderizaria vazio de qualquer jeito. O que falta aqui é exatamente o
// argumento para criar a conta.
export default function AnonymousWorkoutPage() {
  return (
    <Suspense fallback={<LoadingScreen />}>
      <AnonymousWorkoutContent />
    </Suspense>
  );
}

function AnonymousWorkoutContent() {
  const router = useRouter();
  const params = useSearchParams();
  const dayId = params.get("day");

  const [day, setDay] = useState<WorkoutDay | null>(null);
  const [loading, setLoading] = useState(true);
  const [done, setDone] = useState<Set<number>>(new Set());
  const [activeExercise, setActiveExercise] = useState<WorkoutDayExercise | null>(null);
  const [finishing, setFinishing] = useState(false);
  const startedAtRef = useRef<number>(Date.now());
  const firstStartTracked = useRef(false);

  useEffect(() => {
    let active = true;

    (async () => {
      const loaded = dayId
        ? await fetchAnonymousDay(Number(dayId)).then((r) => r.day).catch(() => null)
        : await fetchAnonymousToday().then((r) => r.day).catch(() => null);

      if (!active) return;
      setDay(loaded);
      setLoading(false);
      startedAtRef.current = Date.now();

      if (loaded) {
        trackEvent("workout_started", {
          source: "anonymous",
          workout_day_id: loaded.id ?? undefined,
          exercises_count: loaded.exercises?.length ?? 0,
        });
      }
    })();

    return () => {
      active = false;
    };
  }, [dayId]);

  const exercises = useMemo(() => day?.exercises ?? [], [day]);
  const plannedSets = useMemo(
    () => exercises.reduce((total, exercise) => total + (exercise.sets ?? 0), 0),
    [exercises],
  );

  function toggle(exercise: WorkoutDayExercise) {
    // O primeiro exercício marcado é a métrica primária de ativação do
    // experimento — emitido uma vez só, na transição de zero para um.
    if (!firstStartTracked.current) {
      firstStartTracked.current = true;
      trackEvent("workout_first_exercise_started", {
        source: "anonymous",
        workout_day_id: day?.id ?? undefined,
      });
    }

    // Degrau comparável com /workout/today, que tem séries e esta tela não.
    // Só na transição para marcado: desmarcar é correção, não conclusão.
    if (!done.has(exercise.workout_day_exercise_id)) {
      trackEvent("workout_exercise_completed", {
        source: "anonymous",
        workout_day_id: day?.id ?? undefined,
        workout_day_exercise_id: exercise.workout_day_exercise_id,
        exercise_id: exercise.exercise_id,
      });
    }

    setDone((previous) => {
      const next = new Set(previous);
      if (next.has(exercise.workout_day_exercise_id)) {
        next.delete(exercise.workout_day_exercise_id);
      } else {
        next.add(exercise.workout_day_exercise_id);
      }
      return next;
    });
  }

  async function finish() {
    if (finishing) return;
    setFinishing(true);

    const durationMinutes = Math.max(1, Math.round((Date.now() - startedAtRef.current) / 60_000));
    const completedSets = exercises
      .filter((exercise) => done.has(exercise.workout_day_exercise_id))
      .reduce((total, exercise) => total + (exercise.sets ?? 0), 0);

    try {
      await recordAnonymousSession({
        workout_day_id: day?.id ?? undefined,
        duration_minutes: durationMinutes,
        completion_status: done.size === exercises.length ? "completed" : "completed_partial",
        completed_sets_count: completedSets,
        planned_sets_count: plannedSets,
        source: "anonymous",
        exercise_logs: exercises
          .filter((exercise) => done.has(exercise.workout_day_exercise_id))
          .map((exercise) => ({
            exercise_id: exercise.exercise_id,
            name: exercise.name,
            sets: exercise.sets,
            reps: exercise.reps,
            completed: true,
          })),
      });

      trackEvent("workout_completed", {
        source: "anonymous",
        workout_day_id: day?.id ?? undefined,
        duration_minutes: durationMinutes,
        exercises_count: exercises.length,
      });
    } catch {
      // O treino aconteceu mesmo que o registro não tenha ido. Prender a pessoa
      // numa tela de erro por causa do log seria punir quem fez a parte difícil.
    }

    router.push("/plano/pronto");
  }

  if (loading) return <LoadingScreen />;

  if (!day) {
    return (
      <div style={{ padding: "72px 20px" }}>
        <h1 className="wizard-title">Treino não encontrado</h1>
        <button className="wizard-cta" onClick={() => router.push("/plano/pronto")}>Voltar</button>
      </div>
    );
  }

  return (
    <div style={{ padding: "40px 20px 32px" }}>
      <button
        onClick={() => router.push("/plano/pronto")}
        className="wizard-back"
        style={{ marginBottom: 16 }}
      >
        ← Voltar
      </button>

      <h1 style={{ fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 700, margin: "0 0 4px", letterSpacing: "-0.02em" }}>
        {day.custom_name || day.name}
      </h1>
      <p style={{ fontSize: 13, color: "var(--text-muted)", margin: "0 0 20px" }}>
        {done.size} de {exercises.length} exercícios
      </p>

      <div style={{ display: "flex", flexDirection: "column", gap: 10, marginBottom: 28 }}>
        {exercises.map((exercise) => {
          const completed = done.has(exercise.workout_day_exercise_id);
          return (
            <div
              key={exercise.workout_day_exercise_id}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                background: "var(--surface)",
                border: `1px solid ${completed ? "var(--primary)" : "var(--border)"}`,
                borderRadius: "var(--r-lg)",
                padding: 14,
              }}
            >
              <button
                onClick={() => toggle(exercise)}
                aria-label={completed ? `Desmarcar ${exercise.name}` : `Marcar ${exercise.name} como feito`}
                aria-pressed={completed}
                style={{
                  width: 28, height: 28, flexShrink: 0, borderRadius: 999, cursor: "pointer",
                  border: `2px solid ${completed ? "var(--primary)" : "var(--border)"}`,
                  background: completed ? "var(--primary)" : "transparent",
                  color: "#fff", fontSize: 14, lineHeight: 1,
                }}
              >
                {completed ? "✓" : ""}
              </button>

              <div style={{ flex: 1, minWidth: 0 }}>
                <b style={{ display: "block", fontSize: 15 }}>{exercise.name}</b>
                <span style={{ fontSize: 13, color: "var(--text-muted)" }}>
                  {exercise.sets}x{exercise.reps}
                  {exercise.rest_seconds ? ` · ${exercise.rest_seconds}s descanso` : ""}
                </span>
              </div>

              <button
                onClick={() => setActiveExercise(exercise)}
                aria-label={`Ver detalhes de ${exercise.name}`}
                style={{ background: "transparent", border: 0, color: "var(--text-muted)", cursor: "pointer", fontSize: 18 }}
              >
                ⓘ
              </button>
            </div>
          );
        })}
      </div>

      <button className="wizard-cta" onClick={finish} disabled={finishing || done.size === 0}>
        {finishing ? "Salvando..." : "Concluir treino"}
      </button>

      {activeExercise && (
        <ExerciseInfoModal exercise={activeExercise} onClose={() => setActiveExercise(null)} />
      )}
    </div>
  );
}

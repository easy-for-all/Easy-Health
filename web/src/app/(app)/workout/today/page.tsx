"use client";

/* eslint-disable @next/next/no-img-element */

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { WorkoutDay, WorkoutDayExercise, WorkoutPlan, WorkoutSession } from "@/shared/types/workout";

type Phase = "choose" | "overview" | "exercising" | "rest" | "exercise_feedback" | "done";
type ExerciseOption = {
  id: number;
  name: string;
  muscle_group: string | null;
  exercise_type: string;
  description: string;
  image_url: string;
  muscle_image_url: string;
};
type ExerciseRuntime = {
  planned_sets: number;
  reps_by_set: number[];
  weight_by_set: string[];
  rest_seconds: number;
  feeling: string;
};

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const FEELINGS = [
  { value: "bem", label: "Bem" },
  { value: "cansado", label: "Cansado" },
  { value: "dolorido", label: "Dolorido" },
  { value: "pesado", label: "Pesado" },
  { value: "dor", label: "Com dor" },
];

export default function WorkoutTodayPage() {
  const router = useRouter();
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [sessions, setSessions] = useState<WorkoutSession[]>([]);
  const [day, setDay] = useState<WorkoutDay | null>(null);
  const [loading, setLoading] = useState(true);
  const [phase, setPhase] = useState<Phase>("choose");
  const [currentIndex, setCurrentIndex] = useState(0);
  const [currentSet, setCurrentSet] = useState(1);
  const [restLeft, setRestLeft] = useState(0);
  const [startTime, setStartTime] = useState<Date | null>(null);
  const [exerciseRuntime, setExerciseRuntime] = useState<Record<number, ExerciseRuntime>>({});
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<{ sessions: WorkoutSession[]; total: number }>("/api/v1/workout_sessions?recent=1").catch(() => ({ sessions: [], total: 0 })),
    ]).then(([p, history]) => {
      setPlan(p);
      setSessions(history.sessions ?? []);
    }).finally(() => setLoading(false));
  }, []);

  useEffect(() => () => {
    if (timerRef.current) clearInterval(timerRef.current);
  }, []);

  async function chooseWorkout(workoutDay: WorkoutDay) {
    setLoading(true);
    try {
      const data = await api.get<{ day: WorkoutDay }>(`/api/v1/workout_days/${workoutDay.id}`);
      const runtime = Object.fromEntries((data.day.exercises ?? []).map((exercise) => [
        exercise.workout_day_exercise_id,
        createRuntime(exercise),
      ]));
      setDay(data.day);
      setExerciseRuntime(runtime);
      setCurrentIndex(0);
      setCurrentSet(1);
      setPhase("overview");
    } finally {
      setLoading(false);
    }
  }

  function startWorkout() {
    setStartTime(new Date());
    setPhase("exercising");
  }

  function updateRuntime(wdeId: number, patch: Partial<ExerciseRuntime>) {
    setExerciseRuntime((prev) => ({ ...prev, [wdeId]: { ...prev[wdeId], ...patch } }));
  }

  function updateCurrentSetReps(exercise: WorkoutDayExercise, reps: number) {
    const state = runtimeFor(exerciseRuntime, exercise);
    const repsBySet = [...state.reps_by_set];
    repsBySet[currentSet - 1] = reps;
    updateRuntime(exercise.workout_day_exercise_id, { reps_by_set: repsBySet });
  }

  function updateCurrentSetWeight(exercise: WorkoutDayExercise, weight: string) {
    const state = runtimeFor(exerciseRuntime, exercise);
    const weightBySet = [...state.weight_by_set];
    weightBySet[currentSet - 1] = weight;
    updateRuntime(exercise.workout_day_exercise_id, { weight_by_set: weightBySet });
  }

  function changePlannedSets(exercise: WorkoutDayExercise, nextSets: number) {
    const state = runtimeFor(exerciseRuntime, exercise);
    const plannedSets = Math.max(1, Math.min(12, nextSets));
    const repsBySet = Array.from({ length: plannedSets }, (_, idx) => state.reps_by_set[idx] ?? exercise.reps);
    const weightBySet = Array.from({ length: plannedSets }, (_, idx) => state.weight_by_set[idx] ?? "");
    updateRuntime(exercise.workout_day_exercise_id, { planned_sets: plannedSets, reps_by_set: repsBySet, weight_by_set: weightBySet });
    setCurrentSet((value) => Math.min(value, plannedSets));
  }

  function startRest(seconds: number) {
    setRestLeft(seconds);
    setPhase("rest");
    timerRef.current = setInterval(() => {
      setRestLeft((prev) => {
        if (prev <= 1) {
          if (timerRef.current) clearInterval(timerRef.current);
          setPhase("exercising");
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
  }

  function handleSetDone() {
    if (!day?.exercises) return;
    const exercise = day.exercises[currentIndex];
    const state = runtimeFor(exerciseRuntime, exercise);
    const repsBySet = [...state.reps_by_set];
    repsBySet[currentSet - 1] ||= exercise.reps;
    updateRuntime(exercise.workout_day_exercise_id, { reps_by_set: repsBySet });

    if (currentSet < state.planned_sets) {
      setCurrentSet((s) => s + 1);
      startRest(state.rest_seconds);
    } else {
      setPhase("exercise_feedback");
    }
  }

  function finishExercise(feeling: string) {
    if (!day?.exercises) return;
    const exercise = day.exercises[currentIndex];
    updateRuntime(exercise.workout_day_exercise_id, { feeling });

    if (currentIndex < day.exercises.length - 1) {
      const state = runtimeFor(exerciseRuntime, exercise);
      setCurrentIndex((i) => i + 1);
      setCurrentSet(1);
      startRest(state.rest_seconds);
    } else {
      setPhase("done");
    }
  }

  function skipRest() {
    if (timerRef.current) clearInterval(timerRef.current);
    setPhase("exercising");
  }

  if (loading) return <LoadingScreen />;

  if (!plan?.days?.length) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center px-4 text-center">
        <h1 className="text-2xl font-bold text-gray-900">Nenhum treino disponível</h1>
        <p className="mt-2 text-sm text-gray-500">Crie um planejamento para começar.</p>
        <button onClick={() => router.push("/plan")} className="mt-6 rounded-lg bg-green-500 px-6 py-3 text-sm font-semibold text-white">
          Ver planejamento
        </button>
      </div>
    );
  }

  if (phase === "choose") {
    return <ChooseScreen plan={plan} sessions={sessions} onChoose={chooseWorkout} onBack={() => router.push("/dashboard")} />;
  }

  if (phase === "overview") {
    return (
      <OverviewScreen
        day={day!}
        runtime={exerciseRuntime}
        onChangeRuntime={updateRuntime}
        onChangeDay={(nextDay) => {
          setDay(nextDay);
          setExerciseRuntime((prev) => ({
            ...prev,
            ...Object.fromEntries((nextDay.exercises ?? []).filter((exercise) => !prev[exercise.workout_day_exercise_id]).map((exercise) => [
              exercise.workout_day_exercise_id,
              createRuntime(exercise),
            ])),
          }));
        }}
        onStart={startWorkout}
        onBack={() => setPhase("choose")}
      />
    );
  }

  if (phase === "done") {
    return <DoneScreen day={day!} startTime={startTime ?? new Date()} runtime={exerciseRuntime} onBack={() => router.push("/dashboard")} />;
  }

  const exercises = day!.exercises ?? [];
  const exercise = exercises[currentIndex];
  const runtime = runtimeFor(exerciseRuntime, exercise);

  if (!exercise) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center px-4 text-center">
        <p className="mt-4 text-gray-600">Nenhum exercício encontrado para este treino.</p>
        <button onClick={() => setPhase("overview")} className="mt-4 text-sm text-green-600 hover:underline">
          Voltar
        </button>
      </div>
    );
  }

  if (phase === "rest") {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center px-4">
        <p className="text-sm font-medium uppercase tracking-wide text-gray-400">Descanso</p>
        <p className="mt-4 text-7xl font-bold text-green-500">{restLeft}s</p>
        <p className="mt-2 text-gray-500">Próximo: {exercise.name}</p>
        <button onClick={skipRest} className="mt-8 rounded-lg border border-gray-200 px-6 py-3 text-sm text-gray-500 hover:bg-gray-50">
          Pular descanso
        </button>
        <button onClick={() => setPhase("done")} className="mt-3 text-sm font-medium text-red-500">
          Encerrar treino agora
        </button>
      </div>
    );
  }

  if (phase === "exercise_feedback") {
    return (
      <div className="flex min-h-screen flex-col px-4 py-6">
        <div className="flex flex-1 flex-col justify-center">
          <p className="text-sm font-semibold uppercase tracking-wide text-green-500">Exercício concluído</p>
          <h1 className="mt-2 text-3xl font-bold text-gray-900">{exercise.name}</h1>
          <p className="mt-2 text-gray-500">Como você se sentiu nesse exercício?</p>
          <div className="mt-6 grid grid-cols-2 gap-3">
            {FEELINGS.map((feeling) => (
              <button
                key={feeling.value}
                onClick={() => finishExercise(feeling.value)}
                className="rounded-xl border border-gray-200 bg-white px-4 py-4 text-sm font-semibold text-gray-700 hover:border-green-400"
              >
                {feeling.label}
              </button>
            ))}
          </div>
        </div>
        <button onClick={() => finishExercise("nao_informado")} className="w-full py-3 text-sm text-gray-400">
          Pular
        </button>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col px-4 py-6">
      <div className="mb-4 flex items-center justify-between">
        <span className="text-sm text-gray-500">{currentIndex + 1}/{exercises.length}</span>
        <div className="mx-4 h-1.5 flex-1 rounded-full bg-gray-100">
          <div className="h-1.5 rounded-full bg-green-500 transition-all" style={{ width: `${((currentIndex + 1) / exercises.length) * 100}%` }} />
        </div>
        <button onClick={() => setPhase("done")} className="text-sm font-medium text-red-500">Encerrar</button>
      </div>

      <div className="flex flex-1 flex-col">
        <div className="grid grid-cols-[1fr_104px] gap-3">
          <SmartImage src={exercise.image_url} fallbackSrc={exerciseFallback(exercise)} alt={exercise.name} className="h-48 w-full rounded-xl object-cover" />
          <SmartImage src={exercise.muscle_image_url} fallbackSrc="/muscle-images/cardio.svg" alt={exercise.muscle_group ?? "músculo"} className="h-48 w-full rounded-xl object-cover" />
        </div>
        <p className="mt-5 text-xs font-semibold uppercase tracking-wide text-green-500">{exercise.muscle_group ?? exercise.exercise_type}</p>
        <h2 className="mt-2 text-3xl font-bold text-gray-900">{exercise.name}</h2>
        <p className="mt-2 text-gray-500">{exercise.description}</p>

        <div className="mt-6 grid grid-cols-3 gap-3">
          <AdjustBox label="séries" value={runtime.planned_sets} onMinus={() => changePlannedSets(exercise, runtime.planned_sets - 1)} onPlus={() => changePlannedSets(exercise, runtime.planned_sets + 1)} />
          <AdjustBox label={`reps série ${currentSet}`} value={runtime.reps_by_set[currentSet - 1] ?? exercise.reps} onMinus={() => updateCurrentSetReps(exercise, Math.max(1, (runtime.reps_by_set[currentSet - 1] ?? exercise.reps) - 1))} onPlus={() => updateCurrentSetReps(exercise, (runtime.reps_by_set[currentSet - 1] ?? exercise.reps) + 1)} />
          <Metric label="série atual" value={currentSet} highlight />
        </div>

        <label className="mt-4 block text-sm font-medium text-gray-600">
          Peso na série {currentSet}
          <input
            type="number"
            inputMode="decimal"
            min="0"
            step="0.5"
            value={runtime.weight_by_set[currentSet - 1] ?? ""}
            onChange={(event) => updateCurrentSetWeight(exercise, event.target.value)}
            placeholder="kg"
            className="mt-2 w-full rounded-xl border border-gray-200 px-4 py-3 text-sm focus:border-green-500 focus:outline-none"
          />
        </label>

        <label className="mt-4 block text-sm font-medium text-gray-600">
          Descanso após série
          <input
            type="number"
            min="0"
            step="5"
            value={runtime.rest_seconds}
            onChange={(event) => updateRuntime(exercise.workout_day_exercise_id, { rest_seconds: Number(event.target.value) || 0 })}
            className="mt-2 w-full rounded-xl border border-gray-200 px-4 py-3 text-sm focus:border-green-500 focus:outline-none"
          />
        </label>
      </div>

      <button onClick={handleSetDone} className="w-full rounded-2xl bg-green-500 py-4 text-base font-semibold text-white hover:bg-green-600">
        Feito
      </button>
    </div>
  );
}

function ChooseScreen({
  plan,
  sessions,
  onChoose,
  onBack,
}: {
  plan: WorkoutPlan;
  sessions: WorkoutSession[];
  onChoose: (day: WorkoutDay) => void;
  onBack: () => void;
}) {
  return (
    <div className="min-h-screen px-4 py-6">
      <button onClick={onBack} className="mb-4 text-sm text-gray-500">← Voltar</button>
      <h1 className="text-2xl font-bold text-gray-900">Escolha seu treino</h1>
      <p className="mt-1 text-sm text-gray-500">Faça A, B, C ou qualquer outro que fizer sentido hoje.</p>

      <div className="mt-6 space-y-3">
        {plan.days.map((day, idx) => (
          <button key={day.id} onClick={() => onChoose(day)} className="w-full rounded-xl border border-gray-100 bg-white p-4 text-left hover:border-green-300">
            <div className="flex items-center gap-3">
              <span className="flex h-10 w-10 items-center justify-center rounded-full bg-green-50 font-bold text-green-600">{LETTERS[idx] ?? idx + 1}</span>
              <div>
                <p className="font-semibold text-gray-900">{day.name}</p>
                <p className="text-xs text-gray-500">{day.exercise_count} exercícios</p>
              </div>
            </div>
          </button>
        ))}
      </div>

      <section className="mt-8">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">Últimos 7 dias</h2>
        {sessions.length === 0 ? (
          <p className="mt-3 rounded-xl border border-gray-100 bg-white p-4 text-sm text-gray-500">Nenhum treino registrado nesse período.</p>
        ) : (
          <div className="mt-3 space-y-2">
            {sessions.map((session) => (
              <div key={session.id} className="rounded-xl border border-gray-100 bg-white p-4">
                <p className="font-medium text-gray-900">{session.workout_day_name}</p>
                <p className="text-xs text-gray-500">
                  {new Date(session.completed_at).toLocaleDateString("pt-BR", { weekday: "short", day: "numeric", month: "short" })}
                  {" · "}{session.duration_minutes} min
                  {session.fatigue_level ? ` · cansaço ${session.fatigue_level}/5` : ""}
                </p>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function OverviewScreen({
  day,
  runtime,
  onChangeRuntime,
  onChangeDay,
  onStart,
  onBack,
}: {
  day: WorkoutDay;
  runtime: Record<number, ExerciseRuntime>;
  onChangeRuntime: (wdeId: number, patch: Partial<ExerciseRuntime>) => void;
  onChangeDay: (day: WorkoutDay) => void;
  onStart: () => void;
  onBack: () => void;
}) {
  const [swapMode, setSwapMode] = useState<WorkoutDayExercise | null>(null);
  const [addMode, setAddMode] = useState(false);
  const [alternatives, setAlternatives] = useState<ExerciseOption[]>([]);
  const exercises = day.exercises ?? [];
  const excludeIds = exercises.map((e) => e.exercise_id).join(",");

  async function openSwap(wde: WorkoutDayExercise) {
    const query = wde.muscle_group ? `muscle_group=${wde.muscle_group}` : `exercise_type=${wde.exercise_type}`;
    const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?${query}&exclude_ids=${excludeIds}`);
    setAlternatives(data);
    setSwapMode(wde);
    setAddMode(false);
  }

  async function openAdd() {
    const groups = new Set(exercises.map((e) => e.muscle_group).filter(Boolean));
    const types = new Set(exercises.map((e) => e.exercise_type));
    const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?exclude_ids=${excludeIds}`);
    setAlternatives(data.filter((exercise) => (
      (exercise.muscle_group && groups.has(exercise.muscle_group)) || types.has(exercise.exercise_type)
    )));
    setAddMode(true);
    setSwapMode(null);
  }

  async function doSwap(wdeId: number, replacementId: number) {
    const updated = await api.post<WorkoutDayExercise>(`/api/v1/workout_day_exercises/${wdeId}/swap`, { replacement_exercise_id: replacementId });
    onChangeDay({ ...day, exercises: exercises.map((e) => e.workout_day_exercise_id === wdeId ? updated : e) });
    setSwapMode(null);
  }

  async function doAdd(exerciseId: number) {
    const created = await api.post<WorkoutDayExercise>(`/api/v1/workout_days/${day.id}/exercises`, { exercise_id: exerciseId });
    onChangeDay({ ...day, exercises: [...exercises, created] });
    setAddMode(false);
  }

  return (
    <div className="flex min-h-screen flex-col px-4 py-6">
      <button onClick={onBack} className="mb-4 text-sm text-gray-500">← Escolher outro</button>
      <h1 className="text-2xl font-bold text-gray-900">{day.name}</h1>
      <p className="mt-1 text-sm text-gray-500">{exercises.length} exercícios</p>

      <div className="mt-6 space-y-3">
        {exercises.map((ex) => {
          const state = runtimeFor(runtime, ex);
          return (
            <div key={ex.workout_day_exercise_id} className="rounded-xl border border-gray-100 bg-white p-4">
              <div className="flex gap-3">
                <SmartImage src={ex.image_url} fallbackSrc={exerciseFallback(ex)} alt={ex.name} className="h-16 w-20 rounded-lg object-cover" />
                <SmartImage src={ex.muscle_image_url} fallbackSrc="/muscle-images/cardio.svg" alt={ex.muscle_group ?? "músculo"} className="h-16 w-14 rounded-lg object-cover" />
                <div className="min-w-0 flex-1">
                  <p className="font-semibold text-gray-900">{ex.name}</p>
                  <p className="text-xs text-gray-400">{ex.muscle_group ?? ex.exercise_type} · {state.planned_sets}x{ex.reps} · {state.rest_seconds}s descanso</p>
                </div>
                <button onClick={() => openSwap(ex)} className="text-xs text-blue-500 hover:underline">Trocar</button>
              </div>
              <div className="mt-3 grid grid-cols-2 gap-2">
                {Array.from({ length: state.planned_sets }, (_, idx) => (
                  <label key={idx} className="block text-xs font-medium text-gray-500">
                    Peso série {idx + 1}
                    <input
                      type="number"
                      inputMode="decimal"
                      min="0"
                      step="0.5"
                      value={state.weight_by_set[idx] ?? ""}
                      onChange={(event) => {
                        const weightBySet = [...state.weight_by_set];
                        weightBySet[idx] = event.target.value;
                        onChangeRuntime(ex.workout_day_exercise_id, { weight_by_set: weightBySet });
                      }}
                      placeholder="kg"
                      className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-green-500 focus:outline-none"
                    />
                  </label>
                ))}
              </div>
              <label className="mt-3 block text-xs font-medium text-gray-500">
                Descanso desse exercício
                <input
                  type="number"
                  min="0"
                  step="5"
                  value={state.rest_seconds}
                  onChange={(event) => onChangeRuntime(ex.workout_day_exercise_id, { rest_seconds: Number(event.target.value) || 0 })}
                  className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-green-500 focus:outline-none"
                />
              </label>
            </div>
          );
        })}
      </div>

      <button onClick={openAdd} className="mt-4 w-full rounded-xl border border-dashed border-green-300 py-3 text-sm font-semibold text-green-600">Adicionar exercício</button>

      {(swapMode || addMode) && (
        <div className="fixed inset-0 flex items-end bg-black/40" onClick={() => { setSwapMode(null); setAddMode(false); }}>
          <div className="max-h-[70vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-8 pt-4" onClick={(e) => e.stopPropagation()}>
            <h3 className="mb-4 text-base font-bold text-gray-900">{swapMode ? "Escolha um substituto" : "Adicionar exercício"}</h3>
            {alternatives.length === 0 ? (
              <p className="rounded-lg bg-gray-50 p-3 text-sm text-gray-500">Nenhuma alternativa disponível sem repetir este treino.</p>
            ) : alternatives.map((alt) => (
              <button key={alt.id} onClick={() => swapMode ? doSwap(swapMode.workout_day_exercise_id, alt.id) : doAdd(alt.id)} className="mb-2 flex w-full gap-3 rounded-lg border border-gray-100 p-3 text-left hover:bg-gray-50">
                <SmartImage src={alt.image_url} fallbackSrc={exerciseFallback(alt)} alt={alt.name} className="h-12 w-16 rounded-md object-cover" />
                <div>
                  <p className="font-medium text-gray-900">{alt.name}</p>
                  <p className="text-xs text-gray-400">{alt.muscle_group ?? alt.exercise_type}</p>
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      <button onClick={onStart} className="mt-auto w-full rounded-2xl bg-green-500 py-4 text-base font-semibold text-white hover:bg-green-600">Iniciar treino</button>
    </div>
  );
}

function DoneScreen({
  day,
  startTime,
  runtime,
  onBack,
}: {
  day: WorkoutDay;
  startTime: Date;
  runtime: Record<number, ExerciseRuntime>;
  onBack: () => void;
}) {
  const router = useRouter();
  const [finishedAt] = useState(() => new Date());
  const duration = Math.max(1, Math.round((finishedAt.getTime() - startTime.getTime()) / 60000));
  const [fatigueLevel, setFatigueLevel] = useState(3);
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);
  const exercises = useMemo(() => day.exercises ?? [], [day.exercises]);

  async function handleSave() {
    setSaving(true);
    await api.post("/api/v1/workout_sessions", {
      workout_day_id: day.id,
      duration_minutes: duration,
      fatigue_level: fatigueLevel,
      notes: notes || null,
      completed_at: finishedAt.toISOString(),
      exercise_logs: exercises.map((exercise) => {
        const state = runtimeFor(runtime, exercise);
        return {
          workout_day_exercise_id: exercise.workout_day_exercise_id,
          exercise_id: exercise.exercise_id,
          name: exercise.name,
          weight_kg: firstWeight(state.weight_by_set),
          weight_by_set: state.weight_by_set.map((value) => value ? Number(value) : null),
          planned_sets: exercise.sets,
          sets: state.planned_sets,
          reps: state.reps_by_set,
          rest_seconds: state.rest_seconds,
          feeling: state.feeling || null,
        };
      }),
    });
    router.push("/dashboard");
  }

  return (
    <div className="flex min-h-screen flex-col px-4 py-6">
      <div className="text-center">
        <h1 className="mt-4 text-2xl font-bold text-gray-900">Treino concluído</h1>
        <p className="mt-2 text-gray-500">{day.name} · {duration} min</p>
      </div>

      <div className="mt-6 space-y-3">
        <label className="block text-sm font-semibold text-gray-700">Peso por série</label>
        {exercises.map((exercise) => (
          <div key={exercise.workout_day_exercise_id} className="rounded-xl border border-gray-100 bg-white p-3">
            <span className="text-sm font-medium text-gray-900">{exercise.name}</span>
            <p className="mt-1 text-xs text-gray-400">
              Peso: {formatWeights(runtimeFor(runtime, exercise).weight_by_set)} · Reps: {runtimeFor(runtime, exercise).reps_by_set.join(", ")}
              {runtimeFor(runtime, exercise).feeling ? ` · ${runtimeFor(runtime, exercise).feeling}` : ""}
            </p>
          </div>
        ))}

        <div className="rounded-xl border border-gray-100 bg-white p-4">
          <label className="text-sm font-semibold text-gray-700">Nível geral de cansaço</label>
          <div className="mt-3 flex gap-2">
            {[1, 2, 3, 4, 5].map((level) => (
              <button key={level} onClick={() => setFatigueLevel(level)} className={`h-10 flex-1 rounded-lg text-sm font-bold ${fatigueLevel === level ? "bg-green-500 text-white" : "bg-gray-100 text-gray-500"}`}>
                {level}
              </button>
            ))}
          </div>
        </div>

        <textarea value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Alguma anotação? (opcional)" rows={3} className="w-full rounded-xl border border-gray-200 px-4 py-3 text-sm focus:border-green-500 focus:outline-none" />
        <button onClick={handleSave} disabled={saving} className="w-full rounded-2xl bg-green-500 py-4 text-base font-semibold text-white disabled:opacity-50">
          {saving ? "Salvando..." : "Registrar treino"}
        </button>
        <button onClick={onBack} className="w-full py-2 text-sm text-gray-400">Não registrar</button>
      </div>
    </div>
  );
}

function createRuntime(exercise: WorkoutDayExercise): ExerciseRuntime {
  return {
    planned_sets: exercise.sets,
    reps_by_set: Array.from({ length: exercise.sets }, () => exercise.reps),
    weight_by_set: Array.from({ length: exercise.sets }, () => ""),
    rest_seconds: exercise.rest_seconds,
    feeling: "",
  };
}

function runtimeFor(runtime: Record<number, ExerciseRuntime>, exercise: WorkoutDayExercise): ExerciseRuntime {
  return runtime[exercise.workout_day_exercise_id] ?? createRuntime(exercise);
}

function Metric({ label, value, highlight = false }: { label: string; value: number; highlight?: boolean }) {
  return (
    <div className="flex-1 rounded-xl bg-gray-50 p-4 text-center">
      <p className={`text-2xl font-bold ${highlight ? "text-green-500" : "text-gray-900"}`}>{value}</p>
      <p className="text-xs text-gray-500">{label}</p>
    </div>
  );
}

function AdjustBox({
  label,
  value,
  onMinus,
  onPlus,
}: {
  label: string;
  value: number;
  onMinus: () => void;
  onPlus: () => void;
}) {
  return (
    <div className="rounded-xl bg-gray-50 p-3 text-center">
      <div className="flex items-center justify-center gap-2">
        <button onClick={onMinus} className="flex h-8 w-8 items-center justify-center rounded-full bg-white text-lg font-bold text-gray-500">-</button>
        <p className="min-w-8 text-2xl font-bold text-gray-900">{value}</p>
        <button onClick={onPlus} className="flex h-8 w-8 items-center justify-center rounded-full bg-white text-lg font-bold text-gray-500">+</button>
      </div>
      <p className="mt-1 text-xs text-gray-500">{label}</p>
    </div>
  );
}

function SmartImage({
  src,
  fallbackSrc,
  alt,
  className,
}: {
  src: string;
  fallbackSrc: string;
  alt: string;
  className: string;
}) {
  return (
    <img
      src={src}
      alt={alt}
      className={className}
      onError={(event) => {
        event.currentTarget.onerror = null;
        event.currentTarget.src = fallbackSrc;
      }}
    />
  );
}

function exerciseFallback(exercise: Pick<WorkoutDayExercise, "exercise_type"> | Pick<ExerciseOption, "exercise_type">) {
  return `/exercise-images/${exercise.exercise_type || "treino"}.svg`;
}

function firstWeight(weights: string[]) {
  const first = weights.find((value) => value !== "");
  return first ? Number(first) : null;
}

function formatWeights(weights: string[]) {
  const labels = weights.map((value, idx) => `S${idx + 1}: ${value ? `${value} kg` : "-"}`);
  return labels.join(" · ");
}

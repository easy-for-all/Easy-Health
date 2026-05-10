"use client";

/* eslint-disable @next/next/no-img-element */

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { WorkoutDay, WorkoutDayExercise, WorkoutPlan, WorkoutSession } from "@/shared/types/workout";

type Phase = "choose" | "overview" | "warmup" | "exercising" | "rest" | "exercise_feedback" | "cooldown" | "done";
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
  const [weightError, setWeightError] = useState(false);
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
    setPhase("warmup");
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

    const currentWeight = state.weight_by_set[currentSet - 1];
    if (!currentWeight) {
      setWeightError(true);
      return;
    }
    setWeightError(false);

    const repsBySet = [...state.reps_by_set];
    repsBySet[currentSet - 1] ||= exercise.reps;

    const weightBySet = [...state.weight_by_set];
    if (currentSet < state.planned_sets && !weightBySet[currentSet]) {
      weightBySet[currentSet] = currentWeight;
    }

    updateRuntime(exercise.workout_day_exercise_id, { reps_by_set: repsBySet, weight_by_set: weightBySet });

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
      setPhase("cooldown");
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
        <button onClick={() => router.push("/plan")} className="mt-6 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-white">
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

  if (phase === "warmup") {
    return <WarmupScreen day={day!} onStart={() => setPhase("exercising")} />;
  }

  if (phase === "cooldown") {
    return <CooldownScreen day={day!} onFinish={() => setPhase("done")} />;
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
        <button onClick={() => setPhase("overview")} className="mt-4 text-sm text-primary-600 hover:underline">
          Voltar
        </button>
      </div>
    );
  }

  if (phase === "rest") {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center px-4">
        <p className="text-sm font-medium uppercase tracking-wide text-gray-400">Descanso</p>
        <p className="mt-4 text-7xl font-bold text-primary-500">{restLeft}s</p>
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
          <p className="text-sm font-semibold uppercase tracking-wide text-primary-500">Exercício concluído</p>
          <h1 className="mt-2 text-3xl font-bold text-gray-900">{exercise.name}</h1>
          <p className="mt-2 text-gray-500">Como você se sentiu nesse exercício?</p>
          <div className="mt-6 grid grid-cols-2 gap-3">
            {FEELINGS.map((feeling) => (
              <button
                key={feeling.value}
                onClick={() => finishExercise(feeling.value)}
                className="rounded-xl border border-gray-200 bg-white px-4 py-4 text-sm font-semibold text-gray-700 hover:border-primary-400"
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
          <div className="h-1.5 rounded-full bg-primary-500 transition-all" style={{ width: `${((currentIndex + 1) / exercises.length) * 100}%` }} />
        </div>
        <button onClick={() => setPhase("done")} className="text-sm font-medium text-red-500">Encerrar</button>
      </div>

      <div className="flex flex-1 flex-col">
        <div className="grid grid-cols-[1fr_104px] gap-3">
          <SmartImage src={exercise.image_url} fallbackSrc={exerciseFallback(exercise)} alt={exercise.name} className="h-48 w-full rounded-xl object-cover" />
          <SmartImage src={exercise.muscle_image_url} fallbackSrc="/muscle-images/cardio.svg" alt={exercise.muscle_group ?? "músculo"} className="h-48 w-full rounded-xl object-cover" />
        </div>
        <h2 className="mt-5 text-3xl font-bold text-gray-900">{exercise.name}</h2>
        {(() => {
          const prev = lastExerciseLog(sessions, exercise.exercise_id);
          if (!prev) return null;
          const date = new Date(prev.session.completed_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short" });
          const weight = prev.log.weight_kg ? `${prev.log.weight_kg} kg` : null;
          return (
            <p className="mt-1 text-xs text-gray-400">
              Última vez: {date}{weight ? ` · ${weight}` : ""}
            </p>
          );
        })()}
        <p className="mt-2 text-gray-500">{exercise.description}</p>

        <div className="mt-6 grid grid-cols-3 gap-3">
          <AdjustBox label="séries" value={runtime.planned_sets} onMinus={() => changePlannedSets(exercise, runtime.planned_sets - 1)} onPlus={() => changePlannedSets(exercise, runtime.planned_sets + 1)} />
          <AdjustBox label={`reps série ${currentSet}`} value={runtime.reps_by_set[currentSet - 1] ?? exercise.reps} onMinus={() => updateCurrentSetReps(exercise, Math.max(1, (runtime.reps_by_set[currentSet - 1] ?? exercise.reps) - 1))} onPlus={() => updateCurrentSetReps(exercise, (runtime.reps_by_set[currentSet - 1] ?? exercise.reps) + 1)} />
          <Metric label="série atual" value={currentSet} highlight />
        </div>

        <div className="mt-4">
          <label className="block text-sm font-medium text-gray-600">
            Peso (kg)
            <input
              type="number"
              inputMode="decimal"
              min="0"
              step="0.5"
              value={runtime.weight_by_set[currentSet - 1] ?? ""}
              onChange={(event) => { setWeightError(false); updateCurrentSetWeight(exercise, event.target.value); }}
              placeholder="kg"
              className={`mt-2 w-full rounded-xl border px-4 py-3 text-sm focus:outline-none ${weightError ? "border-red-400 focus:border-red-500" : "border-gray-200 focus:border-primary-500"}`}
            />
          </label>
          {weightError && <p className="mt-1 text-xs text-red-500">Preencha o peso antes de continuar.</p>}
        </div>

        <label className="mt-4 block text-sm font-medium text-gray-600">
          Descanso (s)
          <input
            type="number"
            min="0"
            step="5"
            value={runtime.rest_seconds}
            onChange={(event) => updateRuntime(exercise.workout_day_exercise_id, { rest_seconds: Number(event.target.value) || 0 })}
            className="mt-2 w-full rounded-xl border border-gray-200 px-4 py-3 text-sm focus:border-primary-500 focus:outline-none"
          />
        </label>
      </div>

      <button onClick={handleSetDone} className="w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white hover:bg-primary-600">
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
          <button key={day.id} onClick={() => onChoose(day)} className="w-full rounded-xl border border-gray-100 bg-white p-4 text-left hover:border-primary-300">
            <div className="flex items-center gap-3">
              <span className="flex h-10 w-10 items-center justify-center rounded-full bg-primary-50 font-bold text-primary-600">{LETTERS[idx] ?? idx + 1}</span>
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
  const [aiLoading, setAiLoading] = useState(false);
  const [aiSuggestions, setAiSuggestions] = useState<ExerciseOption[]>([]);
  const exercises = day.exercises ?? [];
  const [globalRest, setGlobalRest] = useState<number>(exercises[0]?.rest_seconds ?? 90);

  async function openSwap(wde: WorkoutDayExercise) {
    const query = wde.muscle_group ? `muscle_group=${wde.muscle_group}` : `exercise_type=${wde.exercise_type}`;
    const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?${query}&exclude_ids=${wde.exercise_id}`);
    setAlternatives(data.slice(0, 3));
    setAiSuggestions([]);
    setSwapMode(wde);
    setAddMode(false);
  }

  async function handleAiPhoto(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file || !swapMode) return;
    setAiLoading(true);
    setAiSuggestions([]);
    try {
      const form = new FormData();
      form.append("image", file);
      form.append("exercise_id", String(swapMode.exercise_id));
      const result = await api.uploadPost<{ suggestions: ExerciseOption[] }>("/api/v1/exercises/ai_substitute", form);
      setAiSuggestions(result.suggestions ?? []);
    } finally {
      setAiLoading(false);
    }
  }

  async function openAdd() {
    const groups = new Set(exercises.map((e) => e.muscle_group).filter(Boolean));
    const types = new Set(exercises.map((e) => e.exercise_type));
    const allIds = exercises.map((e) => e.exercise_id).join(",");
    const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?exclude_ids=${allIds}`);
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

      <div className="mt-4 flex items-center gap-3 rounded-xl border border-gray-100 bg-white px-4 py-3">
        <span className="flex-1 text-sm font-medium text-gray-700">Descanso entre séries</span>
        <input
          type="number"
          min="0"
          step="5"
          value={globalRest}
          onChange={(e) => {
            const v = Number(e.target.value) || 0;
            setGlobalRest(v);
            exercises.forEach((ex) => onChangeRuntime(ex.workout_day_exercise_id, { rest_seconds: v }));
          }}
          className="w-20 rounded-lg border border-gray-200 px-3 py-2 text-right text-sm focus:border-primary-500 focus:outline-none"
        />
        <span className="text-sm text-gray-400">s</span>
      </div>

      <div className="mt-4 space-y-3">
        {exercises.map((ex) => {
          const state = runtimeFor(runtime, ex);
          return (
            <div key={ex.workout_day_exercise_id} className="rounded-xl border border-gray-100 bg-white p-4">
              <div className="flex gap-3">
                <SmartImage src={ex.image_url} fallbackSrc={exerciseFallback(ex)} alt={ex.name} className="h-16 w-20 rounded-lg object-cover" />
                <SmartImage src={ex.muscle_image_url} fallbackSrc="/muscle-images/cardio.svg" alt={ex.muscle_group ?? "músculo"} className="h-16 w-14 rounded-lg object-cover" />
                <div className="min-w-0 flex-1">
                  <p className="font-semibold text-gray-900">{ex.name}</p>
                  <p className="text-xs text-gray-400">{state.planned_sets} séries · {ex.reps} reps</p>
                </div>
                <button onClick={() => openSwap(ex)} className="text-xs text-blue-500 hover:underline">Trocar</button>
              </div>
              <div className="mt-3">
                <label className="block text-xs font-medium text-gray-500">
                  Peso (kg)
                  <input
                    type="number"
                    inputMode="decimal"
                    min="0"
                    step="0.5"
                    value={state.weight_by_set[0] ?? ""}
                    onChange={(event) => {
                      const weight = event.target.value;
                      onChangeRuntime(ex.workout_day_exercise_id, {
                        weight_by_set: Array.from({ length: state.planned_sets }, () => weight),
                      });
                    }}
                    placeholder="kg"
                    className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-primary-500 focus:outline-none"
                  />
                </label>
              </div>
            </div>
          );
        })}
      </div>

      <button onClick={openAdd} className="mt-4 w-full rounded-xl border border-dashed border-primary-300 py-3 text-sm font-semibold text-primary-600">Adicionar exercício</button>

      {(swapMode || addMode) && (
        <div className="fixed inset-0 z-50 flex items-end bg-black/40" onClick={() => { setSwapMode(null); setAddMode(false); }}>
          <div className="max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-24 pt-4" onClick={(e) => e.stopPropagation()}>
            <h3 className="mb-4 text-base font-bold text-gray-900">{swapMode ? "Escolha um substituto" : "Adicionar exercício"}</h3>
            {alternatives.length === 0 ? (
              <p className="rounded-lg bg-gray-50 p-3 text-sm text-gray-500">Nenhuma alternativa disponível.</p>
            ) : alternatives.map((alt) => (
              <button key={alt.id} onClick={() => swapMode ? doSwap(swapMode.workout_day_exercise_id, alt.id) : doAdd(alt.id)} className="mb-2 flex w-full gap-3 rounded-lg border border-gray-100 p-3 text-left hover:bg-gray-50">
                <SmartImage src={alt.image_url} fallbackSrc={exerciseFallback(alt)} alt={alt.name} className="h-12 w-16 rounded-md object-cover" />
                <div>
                  <p className="font-medium text-gray-900">{alt.name}</p>
                  <p className="text-xs text-gray-400">{muscleLabel(alt.muscle_group, alt.exercise_type)}</p>
                </div>
              </button>
            ))}

            {swapMode && (
              <div className="mt-4 border-t border-gray-100 pt-4">
                <p className="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">Tem um aparelho diferente?</p>
                {aiLoading ? (
                  <p className="py-3 text-center text-sm text-gray-400">Analisando foto...</p>
                ) : (
                  <label className="flex cursor-pointer items-center gap-2 rounded-lg border border-dashed border-primary-300 px-4 py-3 text-sm text-primary-600">
                    📷 Enviar foto para IA sugerir substituto
                    <input type="file" accept="image/*" capture="environment" className="hidden" onChange={handleAiPhoto} />
                  </label>
                )}
                {aiSuggestions.map((alt) => (
                  <button key={`ai-${alt.id}`} onClick={() => doSwap(swapMode.workout_day_exercise_id, alt.id)} className="mb-2 mt-2 flex w-full gap-3 rounded-lg border border-primary-100 bg-primary-50 p-3 text-left hover:bg-primary-100">
                    <SmartImage src={alt.image_url} fallbackSrc={exerciseFallback(alt)} alt={alt.name} className="h-12 w-16 rounded-md object-cover" />
                    <div>
                      <p className="font-medium text-gray-900">{alt.name}</p>
                      <p className="text-xs text-primary-500">{muscleLabel(alt.muscle_group, alt.exercise_type)} · sugerido por IA</p>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      <button onClick={onStart} className="mt-auto w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white hover:bg-primary-600">Iniciar treino</button>
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
  const [saveError, setSaveError] = useState("");
  const exercises = useMemo(() => day.exercises ?? [], [day.exercises]);

  async function handleSave() {
    setSaving(true);
    setSaveError("");
    try {
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
    } catch {
      setSaveError("Erro ao salvar o treino. Tente novamente.");
    } finally {
      setSaving(false);
    }
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
              <button key={level} onClick={() => setFatigueLevel(level)} className={`h-10 flex-1 rounded-lg text-sm font-bold ${fatigueLevel === level ? "bg-primary-500 text-white" : "bg-gray-100 text-gray-500"}`}>
                {level}
              </button>
            ))}
          </div>
        </div>

        <textarea value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Alguma anotação? (opcional)" rows={3} className="w-full rounded-xl border border-gray-200 px-4 py-3 text-sm focus:border-primary-500 focus:outline-none" />
        {saveError && <p className="rounded-lg bg-red-50 px-4 py-2 text-sm text-red-700">{saveError}</p>}
        <button onClick={handleSave} disabled={saving} className="w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white disabled:opacity-50">
          {saving ? "Salvando..." : "Registrar treino"}
        </button>
        <button onClick={onBack} className="w-full py-2 text-sm text-gray-400">Não registrar</button>
      </div>
    </div>
  );
}

const WARMUP_BY_TYPE: Record<string, { label: string; duration: string }[]> = {
  musculacao: [
    { label: "Rotação de pescoço", duration: "30s cada lado" },
    { label: "Circundução de ombros", duration: "10 círculos" },
    { label: "Rotação de quadril", duration: "10 círculos" },
    { label: "Agachamento livre (sem peso)", duration: "15 reps" },
    { label: "Polichinelo", duration: "30s" },
  ],
  cardio: [
    { label: "Caminhada lenta", duration: "2 min" },
    { label: "Elevação de joelhos no lugar", duration: "30s" },
    { label: "Chute para trás (calcanhar ao glúteo)", duration: "30s" },
    { label: "Rotação de tornozelos", duration: "10 cada" },
  ],
  corrida: [
    { label: "Caminhada progressiva", duration: "3 min" },
    { label: "Elevação de joelhos", duration: "30s" },
    { label: "Skipping leve", duration: "30s" },
    { label: "Alongamento de panturrilha", duration: "20s cada lado" },
  ],
  default: [
    { label: "Polichinelo", duration: "30s" },
    { label: "Rotação de tronco", duration: "10 cada lado" },
    { label: "Agachamento livre", duration: "10 reps" },
    { label: "Rotação de braços", duration: "10 círculos" },
  ],
};

const COOLDOWN_BY_TYPE: Record<string, { label: string; duration: string }[]> = {
  musculacao: [
    { label: "Alongamento de peito (mãos entrelaçadas atrás)", duration: "30s" },
    { label: "Alongamento de costas (abraço de joelhos)", duration: "30s" },
    { label: "Alongamento de quadríceps", duration: "30s cada lado" },
    { label: "Alongamento de panturrilha", duration: "30s cada lado" },
    { label: "Respiração profunda diafragmática", duration: "1 min" },
  ],
  cardio: [
    { label: "Caminhada lenta para desacelerar", duration: "3 min" },
    { label: "Alongamento de quadríceps", duration: "30s cada lado" },
    { label: "Alongamento de panturrilha", duration: "30s cada lado" },
    { label: "Respiração profunda", duration: "1 min" },
  ],
  corrida: [
    { label: "Caminhada para desacelerar", duration: "3 min" },
    { label: "Alongamento de IT Band", duration: "30s cada lado" },
    { label: "Alongamento de isquiotibiais", duration: "30s" },
    { label: "Alongamento de panturrilha", duration: "30s cada lado" },
  ],
  default: [
    { label: "Respiração profunda", duration: "1 min" },
    { label: "Alongamento de pescoço", duration: "20s cada lado" },
    { label: "Alongamento de tronco", duration: "30s" },
    { label: "Caminhada leve", duration: "2 min" },
  ],
};

function detectWorkoutType(day: WorkoutDay): string {
  const exercises = day.exercises ?? [];
  const types = exercises.map((e) => e.exercise_type);
  if (types.includes("musculacao")) return "musculacao";
  if (types.includes("corrida")) return "corrida";
  if (types.includes("cardio")) return "cardio";
  return "default";
}

function WarmupScreen({ day, onStart }: { day: WorkoutDay; onStart: () => void }) {
  const type = detectWorkoutType(day);
  const items = WARMUP_BY_TYPE[type] ?? WARMUP_BY_TYPE.default;

  return (
    <div className="flex min-h-screen flex-col px-4 py-6">
      <div className="flex flex-1 flex-col">
        <p className="text-xs font-semibold uppercase tracking-wide text-primary-500">Aquecimento</p>
        <h1 className="mt-2 text-2xl font-bold text-gray-900">Prepare o corpo</h1>
        <p className="mt-1 text-sm text-gray-500">Execute os movimentos abaixo antes de começar.</p>

        <div className="mt-6 space-y-3">
          {items.map((item, idx) => (
            <div key={idx} className="flex items-center gap-4 rounded-xl border border-gray-100 bg-white p-4">
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-primary-50 text-sm font-bold text-primary-600">{idx + 1}</span>
              <div>
                <p className="font-medium text-gray-900">{item.label}</p>
                <p className="text-xs text-gray-400">{item.duration}</p>
              </div>
            </div>
          ))}
        </div>
      </div>

      <button onClick={onStart} className="mt-6 w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white hover:bg-primary-600">
        Estou pronto →
      </button>
    </div>
  );
}

function CooldownScreen({ day, onFinish }: { day: WorkoutDay; onFinish: () => void }) {
  const type = detectWorkoutType(day);
  const items = COOLDOWN_BY_TYPE[type] ?? COOLDOWN_BY_TYPE.default;

  return (
    <div className="flex min-h-screen flex-col px-4 py-6">
      <div className="flex flex-1 flex-col">
        <p className="text-xs font-semibold uppercase tracking-wide text-green-600">Finalização</p>
        <h1 className="mt-2 text-2xl font-bold text-gray-900">Recuperação</h1>
        <p className="mt-1 text-sm text-gray-500">Alongamentos e respiração para encerrar o treino.</p>

        <div className="mt-6 space-y-3">
          {items.map((item, idx) => (
            <div key={idx} className="flex items-center gap-4 rounded-xl border border-gray-100 bg-white p-4">
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-green-50 text-sm font-bold text-green-600">{idx + 1}</span>
              <div>
                <p className="font-medium text-gray-900">{item.label}</p>
                <p className="text-xs text-gray-400">{item.duration}</p>
              </div>
            </div>
          ))}
        </div>
      </div>

      <button onClick={onFinish} className="mt-6 w-full rounded-2xl bg-green-500 py-4 text-base font-semibold text-white hover:bg-green-600">
        Finalizar treino →
      </button>
    </div>
  );
}

function lastExerciseLog(sessions: WorkoutSession[], exerciseId: number) {
  const sorted = [...sessions].sort((a, b) => new Date(b.completed_at).getTime() - new Date(a.completed_at).getTime());
  for (const session of sorted) {
    const log = session.exercise_logs?.find((l) => l.exercise_id === exerciseId);
    if (log) return { session, log };
  }
  return null;
}

const MUSCLE_LABELS: Record<string, string> = {
  chest: "Peito", back: "Costas", shoulders: "Ombros",
  biceps: "Bíceps", triceps: "Tríceps", legs: "Pernas", core: "Core",
};

const TYPE_LABELS: Record<string, string> = {
  musculacao: "Musculação", cardio: "Cardio", natacao: "Natação",
  corrida: "Corrida", funcional: "Funcional", caminhada: "Caminhada", hiit: "HIIT",
};

function muscleLabel(muscleGroup: string | null, exerciseType: string): string {
  if (muscleGroup) return MUSCLE_LABELS[muscleGroup] ?? muscleGroup;
  return TYPE_LABELS[exerciseType] ?? exerciseType;
}

function categoryIcon(exerciseType: string, muscleGroup: string | null): string {
  if (muscleGroup) {
    const icons: Record<string, string> = {
      chest: "💪", back: "🏋️", shoulders: "🤸", biceps: "💪", triceps: "💪", legs: "🦵", core: "🧘",
    };
    if (icons[muscleGroup]) return icons[muscleGroup];
  }
  const typeIcons: Record<string, string> = {
    cardio: "❤️", corrida: "🏃", natacao: "🏊", caminhada: "🚶", hiit: "⚡", funcional: "🤸",
  };
  return typeIcons[exerciseType] ?? "🏋️";
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
      <p className={`text-2xl font-bold ${highlight ? "text-primary-500" : "text-gray-900"}`}>{value}</p>
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

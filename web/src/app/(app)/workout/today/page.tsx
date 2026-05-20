"use client";

/* eslint-disable @next/next/no-img-element */

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { WorkoutDay, WorkoutDayExercise, WorkoutPlan, WorkoutSession } from "@/shared/types/workout";
import { WARMUP_BY_TYPE, COOLDOWN_BY_TYPE } from "./warmup-data";
import { SwapModal } from "./swap-modal";
import { ExerciseInfoModal } from "./exercise-info-modal";
import { UpgradeGate } from "@/shared/components/upgrade-gate";
import { useWorkoutSession, formatElapsed } from "@/features/workout/workout-session-context";

type Phase = "choose" | "overview" | "warmup" | "exercising" | "rest" | "exercise_feedback" | "cooldown" | "done";
type ExerciseOption = {
  id: number;
  name: string;
  muscle_group: string | null;
  exercise_type: string;
  description: string;
  instructions?: string | null;
  image_url: string;
  gif_url?: string | null;
  video_url?: string | null;
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
  return <UpgradeGate><WorkoutTodayContent /></UpgradeGate>;
}

function WorkoutTodayContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [sessions, setSessions] = useState<WorkoutSession[]>([]);
  const [day, setDay] = useState<WorkoutDay | null>(null);
  const [loading, setLoading] = useState(true);
  const [phase, setPhase] = useState<Phase>("choose");
  const [currentIndex, setCurrentIndex] = useState(0);
  const [currentSet, setCurrentSet] = useState(1);
  const [restLeft, setRestLeft] = useState(0);
  const { startTime, elapsedSeconds, beginSession, endSession } = useWorkoutSession();
  const [exerciseRuntime, setExerciseRuntime] = useState<Record<number, ExerciseRuntime>>({});
  const [weightError, setWeightError] = useState(false);
  const [showSwapModal, setShowSwapModal] = useState(false);
  const [infoModalExercise, setInfoModalExercise] = useState<WorkoutDayExercise | null>(null);
  const [gifModalExercise, setGifModalExercise] = useState<WorkoutDayExercise | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const audioCtxRef = useRef<AudioContext | null>(null);
  const beepFiredRef = useRef(false);

  useEffect(() => {
    const dayIdParam = searchParams.get("day");
    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<{ sessions: WorkoutSession[]; total: number }>("/api/v1/workout_sessions?recent=1").catch(() => ({ sessions: [], total: 0 })),
    ]).then(async ([p, history]) => {
      setPlan(p);
      setSessions(history.sessions ?? []);
      if (dayIdParam && p?.days) {
        const target = p.days.find((d) => String(d.id) === dayIdParam);
        if (target) {
          try {
            const { day: loaded } = await api.get<{ day: WorkoutDay }>(`/api/v1/workout_days/${target.id}`);
            const runtime = Object.fromEntries((loaded.exercises ?? []).map((ex) => [ex.workout_day_exercise_id, createRuntime(ex)]));
            setDay(loaded);
            setExerciseRuntime(runtime);
            setCurrentIndex(0);
            setCurrentSet(1);
            setPhase("overview");
          } catch { /* fall through to choose screen */ }
        }
      }
    }).finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
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
    unlockAudio();
    if (day) beginSession(day.id);
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

  function unlockAudio() {
    if (audioCtxRef.current) return;
    const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    if (!AudioCtx) return;
    const ctx = new AudioCtx();
    audioCtxRef.current = ctx;
    const buffer = ctx.createBuffer(1, 1, 22050);
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);
    source.start(0);
  }

  function isSoundEnabled(): boolean {
    try { return localStorage.getItem("wk_sound_enabled") !== "false"; } catch { return true; }
  }

  function playBeep() {
    if (!isSoundEnabled()) return;
    const ctx = audioCtxRef.current;
    if (!ctx) return;
    if (ctx.state === "suspended") ctx.resume();

    const playTone = (startOffset: number, freq: number, duration: number) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.4, ctx.currentTime + startOffset);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + startOffset + duration);
      osc.start(ctx.currentTime + startOffset);
      osc.stop(ctx.currentTime + startOffset + duration);
    };

    playTone(0, 880, 0.15);
    playTone(0.2, 1100, 0.25);
  }

  function startRest(seconds: number) {
    setRestLeft(seconds);
    setPhase("rest");
    beepFiredRef.current = false;
    timerRef.current = setInterval(() => {
      setRestLeft((prev) => {
        if (prev <= 1) {
          if (timerRef.current) clearInterval(timerRef.current);
          if (!beepFiredRef.current) {
            beepFiredRef.current = true;
            playBeep();
            navigator.vibrate?.(300);
          }
          setPhase("exercising");
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
  }

  function handleSetDone() {
    unlockAudio();
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

  async function swapDuringExercise(wdeId: number, replacementId: number) {
    const updated = await api.post<WorkoutDayExercise>(`/api/v1/workout_day_exercises/${wdeId}/swap`, { replacement_exercise_id: replacementId });
    setDay((prev) =>
      prev ? { ...prev, exercises: (prev.exercises ?? []).map((e) => e.workout_day_exercise_id === wdeId ? updated : e) } : prev
    );
    setExerciseRuntime((prev) => ({ ...prev, [updated.workout_day_exercise_id]: createRuntime(updated) }));
    setCurrentSet(1);
    setShowSwapModal(false);
  }

  function finishExercise(feeling: string) {
    setShowSwapModal(false);
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
        sessions={sessions}
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
    return <DoneScreen day={day!} startTime={startTime ?? new Date()} runtime={exerciseRuntime} onBack={() => router.push("/dashboard")} onSaved={endSession} />;
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
        <p className="text-xs font-semibold tabular-nums text-primary-600 bg-primary-50 px-3 py-1 rounded-full mb-4">
          Treino: {formatElapsed(elapsedSeconds)}
        </p>
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
    <>
    <div className="flex min-h-screen flex-col px-4 py-6">
      <div className="mb-2 flex items-center justify-between">
        <span className="text-sm text-gray-500">{currentIndex + 1}/{exercises.length}</span>
        <span className="text-xs font-semibold tabular-nums text-primary-600 bg-primary-50 px-2 py-0.5 rounded-full">
          {formatElapsed(elapsedSeconds)}
        </span>
        <button onClick={() => setPhase("done")} className="text-sm font-medium text-red-500">Encerrar</button>
      </div>
      <div className="mb-4 h-1.5 rounded-full bg-gray-100">
        <div className="h-1.5 rounded-full bg-primary-500 transition-all" style={{ width: `${((currentIndex + 1) / exercises.length) * 100}%` }} />
      </div>

      <div className="flex flex-1 flex-col">
        <div className="grid grid-cols-[1fr_104px] gap-3">
          <SmartImage src={exercise.image_url} fallbackSrc={exerciseFallback(exercise)} alt={exercise.name} className="h-48 w-full rounded-xl object-cover" />
          <SmartImage src={exercise.muscle_image_url} fallbackSrc="/muscle-images/cardio.svg" alt={exercise.muscle_group ?? "músculo"} className="h-48 w-full rounded-xl object-cover" />
        </div>
        <div className="mt-2 flex gap-2">
          {(exercise.gif_url || exercise.image_url) && (
            <button
              onClick={() => setGifModalExercise(exercise)}
              className="flex items-center gap-1.5 rounded-full border border-primary-200 bg-primary-50 px-3 py-1.5 text-xs font-semibold text-primary-600 active:bg-primary-100"
            >
              ▶ Ver vídeo
            </button>
          )}
          <button
            onClick={() => setInfoModalExercise(exercise)}
            className="flex items-center gap-1.5 rounded-full border border-gray-200 bg-gray-50 px-3 py-1.5 text-xs font-semibold text-gray-600 active:bg-gray-100"
          >
            ℹ Mais informações
          </button>
          <button
            onClick={() => setShowSwapModal(true)}
            className="flex items-center gap-1.5 rounded-full border border-orange-200 bg-orange-50 px-3 py-1.5 text-xs font-semibold text-orange-600 active:bg-orange-100"
          >
            ⇄ Trocar
          </button>
        </div>
        <div className="mt-4">
          <h2 className="text-3xl font-bold text-gray-900">{exercise.name}</h2>
        </div>
        {(() => {
          const prev = lastExerciseLog(sessions, exercise.exercise_id);
          if (prev) {
            const date = new Date(prev.session.completed_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short" });
            const weight = prev.log.weight_kg ? `${prev.log.weight_kg} kg` : null;
            return (
              <p className="mt-1 text-xs text-gray-400">
                Última vez: {date}{weight ? ` · ${weight}` : ""}
              </p>
            );
          }
          if (exercise.last_performed_at) {
            const daysAgo = Math.floor((Date.now() - new Date(exercise.last_performed_at).getTime()) / 86400000);
            const label = daysAgo === 0 ? "hoje" : daysAgo === 1 ? "ontem" : `há ${daysAgo} dias`;
            return <p className="mt-1 text-xs text-gray-400">Última vez: {label}</p>;
          }
          return null;
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
              className={`mt-2 w-36 rounded-xl border px-4 py-3 text-sm focus:outline-none ${weightError ? "border-red-400 focus:border-red-500" : "border-gray-200 focus:border-primary-500"}`}
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

    <ExerciseInfoModal exercise={infoModalExercise} onClose={() => setInfoModalExercise(null)} />

    {/* Modal fullscreen de mídia */}
    {gifModalExercise && (
      <div
        className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-black/90"
        onClick={() => setGifModalExercise(null)}
      >
        <p className="mb-4 text-sm font-medium text-white/70">{gifModalExercise.name}</p>
        {gifModalExercise.video_url ? (
          <video
            src={gifModalExercise.video_url}
            autoPlay
            loop
            muted
            playsInline
            className="max-h-[70vh] max-w-full rounded-xl object-contain"
          />
        ) : (
          <img
            src={gifModalExercise.gif_url ?? gifModalExercise.image_url}
            alt={gifModalExercise.name}
            className="max-h-[70vh] max-w-full rounded-xl object-contain"
          />
        )}
        <p className="mt-4 text-xs text-white/50">Toque para fechar</p>
      </div>
    )}

    {showSwapModal && (
      <SwapModal
        exercise={exercise}
        onSwap={swapDuringExercise}
        onClose={() => setShowSwapModal(false)}
      />
    )}
    </>
  );
}

function recommendedDayId(plan: WorkoutPlan, sessions: WorkoutSession[]): number | null {
  if (!sessions.length) return plan.days[0]?.id ?? null;
  const lastSession = [...sessions].sort((a, b) => new Date(b.completed_at).getTime() - new Date(a.completed_at).getTime())[0];
  const lastIdx = plan.days.findIndex((d) => d.id === lastSession.workout_day_id);
  if (lastIdx === -1) return plan.days[0]?.id ?? null;
  return plan.days[(lastIdx + 1) % plan.days.length]?.id ?? null;
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
  const recommendedId = recommendedDayId(plan, sessions);

  return (
    <div className="min-h-screen px-4 py-6">
      <button onClick={onBack} className="mb-4 text-sm text-gray-500">← Voltar</button>
      <h1 className="text-2xl font-bold text-gray-900">Escolha seu treino</h1>
      <p className="mt-1 text-sm text-gray-500">Faça A, B, C ou qualquer outro que fizer sentido hoje.</p>

      <div className="mt-6 space-y-3">
        {plan.days.map((day, idx) => {
          const isRecommended = day.id === recommendedId;
          return (
            <button
              key={day.id}
              onClick={() => onChoose(day)}
              className={`w-full rounded-xl border p-4 text-left transition ${isRecommended ? "border-primary-400 bg-primary-50 hover:border-primary-500" : "border-gray-100 bg-white hover:border-primary-300"}`}
            >
              <div className="flex items-center gap-3">
                <span className="flex h-10 w-10 items-center justify-center rounded-full bg-primary-50 font-bold text-primary-600">{LETTERS[idx] ?? idx + 1}</span>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <p className="font-semibold text-gray-900">{day.name}</p>
                    {isRecommended && (
                      <span className="rounded-full bg-primary-500 px-2 py-0.5 text-xs font-semibold text-white">Hoje</span>
                    )}
                  </div>
                  <p className="text-xs text-gray-500">{day.exercise_count} exercícios</p>
                </div>
              </div>
            </button>
          );
        })}
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
  sessions,
  onChangeRuntime,
  onChangeDay,
  onStart,
  onBack,
}: {
  day: WorkoutDay;
  runtime: Record<number, ExerciseRuntime>;
  sessions: WorkoutSession[];
  onChangeRuntime: (wdeId: number, patch: Partial<ExerciseRuntime>) => void;
  onChangeDay: (day: WorkoutDay) => void;
  onStart: () => void;
  onBack: () => void;
}) {
  const [swapMode, setSwapMode] = useState<WorkoutDayExercise | null>(null);
  const [addMode, setAddMode] = useState(false);
  const [addAlternatives, setAddAlternatives] = useState<ExerciseOption[]>([]);
  const [addSearch, setAddSearch] = useState("");
  const [addLoading, setAddLoading] = useState(false);
  const [infoModal, setInfoModal] = useState<WorkoutDayExercise | null>(null);
  const [gifModal, setGifModal] = useState<WorkoutDayExercise | null>(null);
  const exercises = day.exercises ?? [];
  const [globalRest, setGlobalRest] = useState<number>(exercises[0]?.rest_seconds ?? 90);
  const addSearchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  async function openAdd() {
    const groups = new Set(exercises.map((e) => e.muscle_group).filter(Boolean));
    const types = new Set(exercises.map((e) => e.exercise_type));
    const allIds = exercises.map((e) => e.exercise_id).join(",");
    const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?exclude_ids=${allIds}`);
    setAddAlternatives(data.filter((exercise) => (
      (exercise.muscle_group && groups.has(exercise.muscle_group)) || types.has(exercise.exercise_type)
    )));
    setAddMode(true);
    setSwapMode(null);
  }

  function handleAddSearchChange(value: string) {
    setAddSearch(value);
    if (addSearchTimerRef.current) clearTimeout(addSearchTimerRef.current);
    if (value.trim().length >= 2) {
      const allIds = exercises.map((e) => e.exercise_id).join(",");
      addSearchTimerRef.current = setTimeout(async () => {
        setAddLoading(true);
        try {
          const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?name=${encodeURIComponent(value.trim())}&exclude_ids=${allIds}`);
          setAddAlternatives(data);
        } finally {
          setAddLoading(false);
        }
      }, 300);
    }
  }

  function openSwap(wde: WorkoutDayExercise) {
    setSwapMode(wde);
    setAddMode(false);
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
    setAddSearch("");
  }

  async function handleMove(id: number, direction: "up" | "down") {
    const idx = exercises.findIndex((e) => e.workout_day_exercise_id === id);
    if (idx === -1) return;
    if (direction === "up" && idx === 0) return;
    if (direction === "down" && idx === exercises.length - 1) return;
    const newList = [...exercises];
    const swapIdx = direction === "up" ? idx - 1 : idx + 1;
    [newList[idx], newList[swapIdx]] = [newList[swapIdx], newList[idx]];
    onChangeDay({ ...day, exercises: newList });
    try {
      await api.patch(`/api/v1/workout_days/${day.id}/exercises/reorder`, {
        ordered_ids: newList.map((e) => e.workout_day_exercise_id),
      });
    } catch {
      onChangeDay({ ...day, exercises: exercises });
    }
  }

  return (
  <>
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
                  {(() => {
                    const prev = lastExerciseLog(sessions, ex.exercise_id);
                    if (!prev) return <p className="text-xs text-gray-300">Nunca feito</p>;
                    const date = new Date(prev.session.completed_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short" });
                    const weight = prev.log.weight_kg ? ` · ${prev.log.weight_kg} kg` : "";
                    return <p className="text-xs text-gray-300">Última: {date}{weight}</p>;
                  })()}
                </div>
                <div className="flex flex-col items-end gap-1">
                  <button onClick={() => openSwap(ex)} className="text-xs text-blue-500 hover:underline">Trocar</button>
                  <div className="flex gap-1">
                    <button
                      onClick={() => handleMove(ex.workout_day_exercise_id, "up")}
                      disabled={exercises.indexOf(ex) === 0}
                      className="flex h-6 w-6 items-center justify-center rounded border border-gray-200 text-xs text-gray-400 disabled:opacity-25"
                    >↑</button>
                    <button
                      onClick={() => handleMove(ex.workout_day_exercise_id, "down")}
                      disabled={exercises.indexOf(ex) === exercises.length - 1}
                      className="flex h-6 w-6 items-center justify-center rounded border border-gray-200 text-xs text-gray-400 disabled:opacity-25"
                    >↓</button>
                  </div>
                </div>
              </div>
              <div className="mt-2 flex gap-2">
                {(ex.gif_url || ex.image_url) && (
                  <button
                    onClick={() => setGifModal(ex)}
                    className="flex items-center gap-1 rounded-full border border-primary-200 bg-primary-50 px-2.5 py-1 text-xs font-semibold text-primary-600"
                  >
                    ▶ Ver vídeo
                  </button>
                )}
                <button
                  onClick={() => setInfoModal(ex)}
                  className="flex items-center gap-1 rounded-full border border-gray-200 bg-gray-50 px-2.5 py-1 text-xs font-semibold text-gray-600"
                >
                  ℹ Info
                </button>
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
                    className="mt-1 w-28 rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-primary-500 focus:outline-none"
                  />
                </label>
              </div>
            </div>
          );
        })}
      </div>

      <button onClick={openAdd} className="mt-4 w-full rounded-xl border border-dashed border-primary-300 py-3 text-sm font-semibold text-primary-600">Adicionar exercício</button>

      {swapMode && (
        <SwapModal
          exercise={swapMode}
          onSwap={doSwap}
          onClose={() => setSwapMode(null)}
        />
      )}

      {addMode && (
        <div className="fixed inset-0 z-50 flex items-end bg-black/40" onClick={() => { setAddMode(false); setAddSearch(""); }}>
          <div className="max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-24 pt-4" onClick={(e) => e.stopPropagation()}>
            <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-gray-200" />
            <h3 className="mb-3 mt-2 text-base font-bold text-gray-900">Adicionar exercício</h3>

            {/* Campo de busca */}
            <input
              type="text"
              placeholder="Buscar por nome..."
              value={addSearch}
              onChange={(e) => handleAddSearchChange(e.target.value)}
              className="mb-3 w-full rounded-xl border border-gray-200 px-4 py-2.5 text-sm focus:border-primary-500 focus:outline-none"
            />

            {/* Lista de alternativas */}
            {addLoading ? (
              <p className="rounded-lg bg-gray-50 p-3 text-center text-sm text-gray-400">Buscando...</p>
            ) : addAlternatives.length === 0 ? (
              <p className="rounded-lg bg-gray-50 p-3 text-sm text-gray-500">Nenhuma alternativa encontrada.</p>
            ) : (
              addAlternatives.map((alt) => (
                <button key={alt.id} onClick={() => doAdd(alt.id)} className="mb-2 flex w-full gap-3 rounded-lg border border-gray-100 p-3 text-left hover:bg-gray-50">
                  <SmartImage src={alt.image_url} fallbackSrc={exerciseFallback(alt)} alt={alt.name} className="h-12 w-16 rounded-md object-cover" />
                  <div>
                    <p className="font-medium text-gray-900">{alt.name}</p>
                    <p className="text-xs text-gray-400">{muscleLabel(alt.muscle_group, alt.exercise_type)}</p>
                  </div>
                </button>
              ))
            )}
          </div>
        </div>
      )}

      <button onClick={onStart} className="mt-auto w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white hover:bg-primary-600">Iniciar treino</button>
    </div>
    <ExerciseInfoModal exercise={infoModal} onClose={() => setInfoModal(null)} />

    {gifModal && (
      <div className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-black/90" onClick={() => setGifModal(null)}>
        <p className="mb-4 text-sm font-medium text-white/70">{gifModal.name}</p>
        {gifModal.video_url ? (
          <video src={gifModal.video_url} autoPlay loop muted playsInline className="max-h-[70vh] max-w-full rounded-xl object-contain" />
        ) : (
          <img src={gifModal.gif_url ?? gifModal.image_url} alt={gifModal.name} className="max-h-[70vh] max-w-full rounded-xl object-contain" />
        )}
        <p className="mt-4 text-xs text-white/50">Toque para fechar</p>
      </div>
    )}
  </>
  );
}

function DoneScreen({
  day,
  startTime,
  runtime,
  onBack,
  onSaved,
}: {
  day: WorkoutDay;
  startTime: Date;
  runtime: Record<number, ExerciseRuntime>;
  onBack: () => void;
  onSaved?: () => void;
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
    onSaved?.();
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
            <div key={idx} className="flex items-center gap-3 rounded-xl border border-gray-100 bg-white overflow-hidden shadow-sm">
              <img
                src={item.thumbnail}
                alt={item.label}
                className="h-20 w-24 flex-shrink-0 object-cover"
                onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
              />
              <div className="flex items-center gap-3 py-3 pr-4">
                <span className="flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full bg-primary-50 text-xs font-bold text-primary-600">{idx + 1}</span>
                <div>
                  <p className="font-medium text-gray-900 text-sm">{item.label}</p>
                  <p className="text-xs text-primary-400 mt-0.5">{item.duration}</p>
                </div>
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
            <div key={idx} className="flex items-center gap-3 rounded-xl border border-gray-100 bg-white overflow-hidden shadow-sm">
              <img
                src={item.thumbnail}
                alt={item.label}
                className="h-20 w-24 flex-shrink-0 object-cover"
                onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
              />
              <div className="flex items-center gap-3 py-3 pr-4">
                <span className="flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full bg-green-50 text-xs font-bold text-green-600">{idx + 1}</span>
                <div>
                  <p className="font-medium text-gray-900 text-sm">{item.label}</p>
                  <p className="text-xs text-green-400 mt-0.5">{item.duration}</p>
                </div>
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

function resolveImageSrc(src: string): string {
  return src;
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
      src={resolveImageSrc(src)}
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

"use client";

/* eslint-disable @next/next/no-img-element */

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { api, ApiError } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { WorkoutDay, WorkoutDayExercise, WorkoutPlan, WorkoutSession } from "@/shared/types/workout";
import { WARMUP_BY_TYPE, COOLDOWN_BY_TYPE } from "./warmup-data";
import { SwapModal } from "./swap-modal";
import { ExerciseInfoModal } from "@/shared/components/workout/exercise-info-modal";
import { UpgradeGate, UpgradeBanner } from "@/shared/components/upgrade-gate";
import { useAuth } from "@/features/auth/auth-context";
import { useWorkoutSession, formatElapsed } from "@/features/workout/workout-session-context";
import { ProgressiveProfilingSheet } from "@/features/workout/progressive-profiling-sheet";
import { AnimatedCounter, ConfettiBurst, GlowPulse, PressButton } from "@/shared/components/motion";
import { ShareButton } from "@/shared/components/workout-share/share-button";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { getGymSafeImageUrl } from "@/shared/utils/exercise-image";
import { relativeDate } from "@/shared/utils/relative-date";
import { historyWeight } from "@/features/workout/use-exercise-history";
import { AITrainerAvatar, AITrainerBubble } from "@/shared/components/ai-trainer";
import { useCoach } from "@/features/coach/coach-context";
import { AgentOrb } from "@/shared/components/agent-orb";
import "@/shared/components/workout/workout-ui.css";
import { workoutEngine, usesTimerScreen, usesRecoveryScreen } from "@/features/workout/workout-engine";
import { CardioPanel, IntervalPanel, RecoveryPanel } from "./workout-engine-screens";

type Phase = "choose" | "overview" | "warmup" | "exercising" | "rest" | "exercise_feedback" | "cooldown" | "closing_optional" | "pre_done" | "done";
type ExerciseOption = {
  id: number;
  name: string;
  muscle_group: string | null;
  exercise_type: string;
  equipment_type?: string | null;
  description: string;
  instructions?: string | null;
  image_url: string;
  gif_url?: string | null;
  video_url?: string | null;
  muscle_image_url: string;
  is_favorite?: boolean;
};
type ExerciseRuntime = {
  planned_sets: number;
  reps_by_set: number[];
  weight_by_set: string[];
  warmup_by_set: boolean[];
  rest_seconds: number;
  feeling: string;
  duration_minutes?: number;
  intensity?: string;
  elapsed_seconds?: number;
};

const MUSCLE_COLORS: Record<string, string> = {
  chest: "bg-red-100 text-red-700",
  back: "bg-blue-100 text-blue-700",
  shoulders: "bg-purple-100 text-purple-700",
  biceps: "bg-yellow-100 text-yellow-700",
  triceps: "bg-orange-100 text-orange-700",
  legs: "bg-green-100 text-green-700",
  core: "bg-teal-100 text-teal-700",
};

function isCardio(ex: WorkoutDayExercise) { return usesTimerScreen(ex); }
function isTimed(ex: WorkoutDayExercise)  { return usesRecoveryScreen(ex); }
function isInterval(ex: WorkoutDayExercise) { return workoutEngine(ex) === "interval"; }

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// ── Rest timer dynamic messages ─────────────────────────────────────────────
interface RestCtx {
  exerciseName: string;
  muscleGroup?: string | null;
  isLastExercise: boolean;
  isWarmup?: boolean;
}

const REST_MOTIVATIONAL_MESSAGES = [
  "Respira fundo. Você está indo muito bem.",
  "Recupere o fôlego. A próxima série vai ser ainda melhor.",
  "Mantenha o foco. Cada série conta.",
  "Descanse e prepare-se. Você está construindo algo grande.",
  "Acredite no processo. Você está evoluindo.",
  "Um passo de cada vez. Continue firme.",
  "Você está mais forte do que imagina.",
  "Essa pausa é parte do treino. Use-a bem.",
  "Concentre-se. A próxima série é sua.",
  "Disciplina é o que faz a diferença.",
  "Dor passageira, progresso duradouro.",
  "Respira. Você tem isso.",
  "Cada repetição te deixa mais perto do objetivo.",
  "O desconforto de hoje é o resultado de amanhã.",
  "Você escolheu estar aqui. Isso já é vitória.",
  "Mantenha a técnica. Qualidade antes de quantidade.",
  "Foco total na próxima série.",
  "Você está fazendo o trabalho. Continue.",
  "Mente forte, corpo forte.",
  "Recupere. Respire. Vá em frente.",
];

function getRestMessage(ctx: RestCtx): string {
  const { exerciseName, isLastExercise, isWarmup } = ctx;

  if (isWarmup) return "Aquecimento concluído. Inicie a carga principal com técnica limpa.";
  if (isLastExercise) return "Treino quase encerrado. Dê tudo na última etapa.";

  const idx = exerciseName.length % REST_MOTIVATIONAL_MESSAGES.length;
  return REST_MOTIVATIONAL_MESSAGES[idx];
}

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
  const { setScreen, registerExec, open } = useCoach();
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [sessions, setSessions] = useState<WorkoutSession[]>([]);
  const [day, setDay] = useState<WorkoutDay | null>(null);
  const [loading, setLoading] = useState(true);
  const [redirecting, setRedirecting] = useState(false);
  const [phase, setPhase] = useState<Phase>("choose");
  const [currentIndex, setCurrentIndex] = useState(0);
  const [currentSet, setCurrentSet] = useState(1);
  const [restLeft, setRestLeft] = useState(0);
  const [restTotal, setRestTotal] = useState(0);
  const [setFlash, setSetFlash] = useState(false);
  const { startTime, elapsedSeconds, beginSession, endSession, saveRestEnd, getRestEnd } = useWorkoutSession();
  const [restAlert, setRestAlert] = useState(false);
  const [exerciseRuntime, setExerciseRuntime] = useState<Record<number, ExerciseRuntime>>({});
  const [weightError, setWeightError] = useState(false);
  const [showSwapModal, setShowSwapModal] = useState(false);
  const [showSwapChoice, setShowSwapChoice] = useState(false);
  const [infoModalExercise, setInfoModalExercise] = useState<WorkoutDayExercise | null>(null);
  const [gifModalExercise, setGifModalExercise] = useState<WorkoutDayExercise | null>(null);
  const [showReorderModal, setShowReorderModal] = useState(false);
  const [reorderSwapTarget, setReorderSwapTarget] = useState<WorkoutDayExercise | null>(null);
  const [showReorderAdd, setShowReorderAdd] = useState(false);
  const [reorderAddAlternatives, setReorderAddAlternatives] = useState<ExerciseOption[]>([]);
  const [reorderAddSearch, setReorderAddSearch] = useState("");
  const [reorderAddLoading, setReorderAddLoading] = useState(false);
  const [reorderAddMuscleFilter, setReorderAddMuscleFilter] = useState<string | null>(null);
  const [reorderAddDupeMsg, setReorderAddDupeMsg] = useState<string | null>(null);
  const reorderAddTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [cardioTimeLeft, setCardioTimeLeft] = useState(0);
  const [timedElapsed, setTimedElapsed] = useState(0);
  const [extraBlockType, setExtraBlockType] = useState<"cardio" | "abs" | null>(null);
  const [extraBlockData, setExtraBlockData] = useState<Record<string, unknown> | null>(null);
  const [timedRunning, setTimedRunning] = useState(false);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const cardioTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const timedTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const audioCtxRef = useRef<AudioContext | null>(null);
  const beepFiredRef = useRef(false);

  const sessionVolume = useMemo(() => {
    if (!day?.exercises) return 0;
    let total = 0;
    day.exercises.forEach((ex, idx) => {
      if (isCardio(ex) || isTimed(ex)) return;
      const state = runtimeFor(exerciseRuntime, ex);
      const setsCompleted = idx < currentIndex ? state.planned_sets : (idx === currentIndex ? currentSet - 1 : 0);
      for (let s = 0; s < setsCompleted; s++) {
        total += (Number(state.weight_by_set[s]) || 0) * (state.reps_by_set[s] || 0);
      }
    });
    return Math.round(total);
  }, [day?.exercises, exerciseRuntime, currentIndex, currentSet]);

  useEffect(() => {
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "treino" });
  }, []);

  // Register coach exec context whenever the exercising phase or current exercise changes
  useEffect(() => {
    if (phase === "exercising" && day?.exercises) {
      const ex = day.exercises[currentIndex];
      if (ex) {
        setScreen("exec");
        registerExec(
          {
            exerciseId: ex.exercise_id,
            workoutDayExerciseId: ex.workout_day_exercise_id,
            exerciseName: ex.name,
            muscleGroup: ex.muscle_group,
            exerciseType: ex.exercise_type,
            currentIndex,
            totalExercises: day.exercises.length,
            setInfo: (() => {
              const ps = runtimeFor(exerciseRuntime, ex).planned_sets;
              return ps ? `Série ${currentSet} de ${ps}` : `Série ${currentSet}`;
            })(),
          },
          (wdeId, newExerciseId) => swapDuringExercise(wdeId, newExerciseId)
        );
      }
    } else if (phase === "overview" || phase === "warmup") {
      setScreen("day");
      registerExec(null, null);
    } else if (phase === "done" || phase === "pre_done" || phase === "choose") {
      setScreen("dashboard");
      registerExec(null, null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, currentIndex, currentSet, day?.exercises]);

  useEffect(() => {
    const dayIdParam = searchParams.get("day");
    const quickParam = searchParams.get("quick");

    // Handle quick workout: day data was pre-generated and stored in sessionStorage
    if (quickParam === "1") {
      const raw = sessionStorage.getItem("wk_quick_day");
      if (!raw) {
        router.replace("/workout/quick");
        return;
      }
      try {
        const quickDay: WorkoutDay = JSON.parse(raw);
        const runtime = Object.fromEntries((quickDay.exercises ?? []).map((ex) => [ex.workout_day_exercise_id, createRuntime(ex)]));
        setPlan(null);
        setSessions([]);
        setDay(quickDay);
        setExerciseRuntime(runtime);
        setCurrentIndex(0);
        setCurrentSet(1);
        beginSession(null);
        setPhase("warmup");
        setLoading(false);
        return;
      } catch {
        router.replace("/workout/quick");
        return;
      }
    }

    // Pre-start rest interval immediately (accurate countdown regardless of API latency)
    const restEnd = getRestEnd();
    if (restEnd && restEnd > Date.now()) {
      const remaining = Math.ceil((restEnd - Date.now()) / 1000);
      setRestLeft(remaining);
      beepFiredRef.current = false;
      if (timerRef.current) clearInterval(timerRef.current);
      timerRef.current = setInterval(() => {
        setRestLeft((prev) => {
          if (prev <= 1) {
            if (timerRef.current) clearInterval(timerRef.current);
            saveRestEnd(null);
            if (!beepFiredRef.current) {
              beepFiredRef.current = true;
              playBeep();
              navigator.vibrate?.(300);
              setRestAlert(true);
              setTimeout(() => { setRestAlert(false); setPhase("exercising"); }, 2000);
            }
            return 0;
          }
          return prev - 1;
        });
      }, 1000);
    }

    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<{ sessions: WorkoutSession[]; total: number }>("/api/v1/workout_sessions?recent=1&status=completed").catch(() => ({ sessions: [], total: 0 })),
    ]).then(async ([p, history]) => {
      setPlan(p);
      setSessions(history.sessions ?? []);
      if (dayIdParam && p?.days) {
        const target = p.days.find((d) => String(d.id) === dayIdParam);
        if (target) {
          try {
            const { day: loaded } = await api.get<{ day: WorkoutDay }>(`/api/v1/workout_days/${target.id}`);
            const runtime = Object.fromEntries((loaded.exercises ?? []).map((ex) => [ex.workout_day_exercise_id, createRuntime(ex, historyWeight(ex))]));
            setDay(loaded);
            setExerciseRuntime(runtime);
            setCurrentIndex(0);
            setCurrentSet(1);
            setPhase("overview");
          } catch { /* fall through to choose screen */ }
        }
      } else {
        // Restore active workout session if user navigated away mid-workout
        const storedStartTs = sessionStorage.getItem("wk_start_ts");
        const storedDayId = sessionStorage.getItem("wk_day_id");
        const storedPhase = sessionStorage.getItem("wk_phase") as Phase | null;

        if (storedStartTs && storedDayId && storedPhase && storedPhase !== "done" && storedPhase !== "pre_done" && storedPhase !== "choose") {
          try {
            const { day: loaded } = await api.get<{ day: WorkoutDay }>(`/api/v1/workout_days/${storedDayId}`);

            // Restore exercise order
            let exercises = loaded.exercises ?? [];
            const storedOrderRaw = sessionStorage.getItem("wk_exercises_order");
            if (storedOrderRaw) {
              try {
                const orderIds: number[] = JSON.parse(storedOrderRaw);
                const orderMap = new Map(orderIds.map((id, i) => [id, i]));
                exercises = [...exercises].sort((a, b) =>
                  (orderMap.get(a.workout_day_exercise_id) ?? 999) - (orderMap.get(b.workout_day_exercise_id) ?? 999)
                );
              } catch { /* use API order */ }
            }

            // Build runtime: defaults merged with saved state
            const defaultRuntime = Object.fromEntries(exercises.map((ex) => [ex.workout_day_exercise_id, createRuntime(ex, historyWeight(ex))]));
            const storedRuntimeRaw = sessionStorage.getItem("wk_exercise_runtime");
            let restoredRuntime = defaultRuntime;
            if (storedRuntimeRaw) {
              try {
                const parsed = JSON.parse(storedRuntimeRaw) as Record<string, ExerciseRuntime>;
                restoredRuntime = {
                  ...defaultRuntime,
                  ...Object.fromEntries(Object.entries(parsed).map(([k, v]) => [Number(k), v])),
                };
              } catch { /* use defaults */ }
            }

            setDay({ ...loaded, exercises });
            setExerciseRuntime(restoredRuntime);
            setCurrentIndex(Math.max(0, parseInt(sessionStorage.getItem("wk_current_index") ?? "0", 10)));
            setCurrentSet(Math.max(1, parseInt(sessionStorage.getItem("wk_current_set") ?? "1", 10)));

            // If rest timer is still active, go to rest phase; otherwise restore saved phase
            const currentRestEnd = getRestEnd();
            if (currentRestEnd && currentRestEnd > Date.now()) {
              const remaining = Math.ceil((currentRestEnd - Date.now()) / 1000);
              setRestLeft(remaining);
              setRestTotal(remaining);
              setPhase("rest");
            } else {
              setPhase(storedPhase);
            }
          } catch {
            try {
              ["wk_start_ts","wk_day_id","wk_phase","wk_current_index","wk_current_set","wk_exercise_runtime","wk_exercises_order"].forEach((k) => sessionStorage.removeItem(k));
            } catch { /* ignore */ }
          }
        }
      }
    }).finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => () => {
    if (timerRef.current) clearInterval(timerRef.current);
    if (cardioTimerRef.current) clearInterval(cardioTimerRef.current);
    if (reorderAddTimerRef.current) clearTimeout(reorderAddTimerRef.current);
  }, []);

  // Redirect to central hub when there is no active session and no day param
  useEffect(() => {
    if (!loading && phase === "choose") {
      setRedirecting(true);
      router.replace("/workouts");
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loading, phase]);

  // Persist workout state so it can be restored if user navigates away mid-workout
  useEffect(() => {
    if (!startTime || !day) return;
    if (phase === "choose" || phase === "done" || phase === "pre_done") return;
    try {
      sessionStorage.setItem("wk_phase", phase);
      sessionStorage.setItem("wk_current_index", String(currentIndex));
      sessionStorage.setItem("wk_current_set", String(currentSet));
      sessionStorage.setItem("wk_exercise_runtime", JSON.stringify(exerciseRuntime));
      sessionStorage.setItem("wk_exercises_order", JSON.stringify((day.exercises ?? []).map((e) => e.workout_day_exercise_id)));
    } catch { /* storage unavailable */ }
  }, [startTime, phase, currentIndex, currentSet, exerciseRuntime, day]);

  // Reset timed exercise state when switching to a new timed exercise
  useEffect(() => {
    if (phase !== "exercising") return;
    const ex = day?.exercises?.[currentIndex];
    if (!ex || !isTimed(ex)) return;
    if (timedTimerRef.current) clearInterval(timedTimerRef.current);
    setTimedElapsed(0);
    setTimedRunning(false);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentIndex, phase]);

  // Run timed exercise counter when active
  useEffect(() => {
    if (!timedRunning) return;
    timedTimerRef.current = setInterval(() => {
      setTimedElapsed((prev) => prev + 1);
    }, 1000);
    return () => {
      if (timedTimerRef.current) clearInterval(timedTimerRef.current);
    };
  }, [timedRunning]);

  // Auto-start cardio timer when switching to a cardio exercise in exercising phase
  useEffect(() => {
    if (phase !== "exercising") return;
    const ex = day?.exercises?.[currentIndex];
    if (!ex || !isCardio(ex)) return;
    const mins = ex.duration_minutes ?? 20;
    setCardioTimeLeft(mins * 60);
    if (cardioTimerRef.current) clearInterval(cardioTimerRef.current);
    cardioTimerRef.current = setInterval(() => {
      setCardioTimeLeft((prev) => {
        if (prev <= 1) {
          if (cardioTimerRef.current) clearInterval(cardioTimerRef.current);
          playBeep();
          navigator.vibrate?.([200, 100, 200]);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => {
      if (cardioTimerRef.current) clearInterval(cardioTimerRef.current);
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentIndex, phase]);

  async function chooseWorkout(workoutDay: WorkoutDay) {
    setLoading(true);
    try {
      const data = await api.get<{ day: WorkoutDay }>(`/api/v1/workout_days/${workoutDay.id}`);
      const runtime = Object.fromEntries((data.day.exercises ?? []).map((exercise) => [
        exercise.workout_day_exercise_id,
        createRuntime(exercise, historyWeight(exercise)),
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

  async function toggleFavoriteWorkoutDay(dayId: number) {
    if (!plan) return;
    const prev = plan.days.find((d) => d.id === dayId)?.favorited ?? false;
    // Optimistic update
    setPlan((p) => p ? { ...p, days: p.days.map((d) => d.id === dayId ? { ...d, favorited: !prev } : d) } : p);
    try {
      const resp = await api.patch<{ favorited: boolean }>(`/api/v1/workout_days/${dayId}/toggle_favorite`, {});
      setPlan((p) => p ? { ...p, days: p.days.map((d) => d.id === dayId ? { ...d, favorited: resp.favorited } : d) } : p);
    } catch {
      // Revert on error
      setPlan((p) => p ? { ...p, days: p.days.map((d) => d.id === dayId ? { ...d, favorited: prev } : d) } : p);
    }
  }

  function startWorkout() {
    unlockAudio();
    if (day) {
      beginSession(day.id);
      trackEvent(EVENTS.WORKOUT_STARTED, {
        workout_day_id: day.id ?? undefined,
        workout_name: day.name,
        exercises_count: day.exercises?.length ?? 0,
        source: "workout_today",
      });
    }
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
    const warmupBySet = Array.from({ length: plannedSets }, (_, idx) => state.warmup_by_set?.[idx] ?? false);
    updateRuntime(exercise.workout_day_exercise_id, { planned_sets: plannedSets, reps_by_set: repsBySet, weight_by_set: weightBySet, warmup_by_set: warmupBySet });
    setCurrentSet((value) => Math.min(value, plannedSets));
  }

  function toggleWarmup(exercise: WorkoutDayExercise, setIdx: number) {
    const state = runtimeFor(exerciseRuntime, exercise);
    const warmup = [...(state.warmup_by_set ?? Array.from({ length: state.planned_sets }, () => false))];
    warmup[setIdx] = !warmup[setIdx];
    updateRuntime(exercise.workout_day_exercise_id, { warmup_by_set: warmup });
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
    setRestTotal(seconds);
    setRestAlert(false);
    setPhase("rest");
    beepFiredRef.current = false;
    saveRestEnd(Date.now() + seconds * 1000);
    if (timerRef.current) clearInterval(timerRef.current);
    timerRef.current = setInterval(() => {
      setRestLeft((prev) => {
        if (prev <= 1) {
          if (timerRef.current) clearInterval(timerRef.current);
          saveRestEnd(null);
          if (!beepFiredRef.current) {
            beepFiredRef.current = true;
            playBeep();
            navigator.vibrate?.(300);
            setRestAlert(true);
            setTimeout(() => {
              setRestAlert(false);
              setPhase("exercising");
            }, 2000);
          }
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
    if (!isCardio(exercise) && !currentWeight) {
      setWeightError(true);
      return;
    }
    setWeightError(false);

    const repsBySet = [...state.reps_by_set];
    repsBySet[currentSet - 1] ||= exercise.reps;

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

    updateRuntime(exercise.workout_day_exercise_id, { reps_by_set: repsBySet, weight_by_set: weightBySet });

    navigator.vibrate?.(80);
    setSetFlash(true);
    setTimeout(() => setSetFlash(false), 600);

    if (currentSet < state.planned_sets) {
      setCurrentSet((s) => s + 1);
      startRest(state.rest_seconds);
    } else {
      setPhase("exercise_feedback");
    }
  }

  async function handleMoveExercising(wdeId: number, direction: "up" | "down") {
    if (!day) return;
    const list = day.exercises ?? [];
    const idx = list.findIndex((e) => e.workout_day_exercise_id === wdeId);
    if (idx === -1) return;
    if (direction === "up" && idx === 0) return;
    if (direction === "down" && idx === list.length - 1) return;
    const newList = [...list];
    const swapIdx = direction === "up" ? idx - 1 : idx + 1;
    [newList[idx], newList[swapIdx]] = [newList[swapIdx], newList[idx]];
    const currentExId = list[currentIndex]?.workout_day_exercise_id;
    const newCurrentIndex = currentExId != null
      ? newList.findIndex((e) => e.workout_day_exercise_id === currentExId)
      : currentIndex;
    setDay({ ...day, exercises: newList });
    if (newCurrentIndex >= 0 && newCurrentIndex !== currentIndex) {
      setCurrentIndex(newCurrentIndex);
    }
    try {
      await api.patch(`/api/v1/workout_days/${day.id}/exercises/reorder`, {
        ordered_ids: newList.map((e) => e.workout_day_exercise_id),
      });
    } catch {
      setDay(day);
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

  async function removeExerciseDuring(wdeId: number) {
    if (!day) return;
    const list = day.exercises ?? [];
    if (list.length <= 1) return;
    const currentExId = list[currentIndex]?.workout_day_exercise_id;
    const newList = list.filter((e) => e.workout_day_exercise_id !== wdeId);
    let newCurrentIndex: number;
    if (currentExId === wdeId) {
      newCurrentIndex = Math.min(currentIndex, newList.length - 1);
      setCurrentSet(1);
    } else {
      newCurrentIndex = Math.max(0, newList.findIndex((e) => e.workout_day_exercise_id === currentExId));
    }
    setDay({ ...day, exercises: newList });
    setCurrentIndex(newCurrentIndex);
    try {
      await api.delete(`/api/v1/workout_day_exercises/${wdeId}`);
    } catch {
      setDay(day);
      setCurrentIndex(currentIndex);
    }
  }

  async function swapFromReorder(wdeId: number, replacementId: number) {
    const updated = await api.post<WorkoutDayExercise>(`/api/v1/workout_day_exercises/${wdeId}/swap`, { replacement_exercise_id: replacementId });
    setDay((prev) =>
      prev ? { ...prev, exercises: (prev.exercises ?? []).map((e) => e.workout_day_exercise_id === wdeId ? updated : e) } : prev
    );
    setExerciseRuntime((prev) => ({ ...prev, [updated.workout_day_exercise_id]: createRuntime(updated) }));
    if (wdeId === (day?.exercises ?? [])[currentIndex]?.workout_day_exercise_id) {
      setCurrentSet(1);
    }
    setReorderSwapTarget(null);
  }

  async function openReorderAdd() {
    if (!day) return;
    const allIds = (day.exercises ?? []).map((e) => e.exercise_id).join(",");
    const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?exclude_ids=${allIds}`);
    setReorderAddAlternatives(data);
    setReorderAddSearch("");
    setReorderAddMuscleFilter(null);
    setReorderAddDupeMsg(null);
    setShowReorderAdd(true);
  }

  function handleReorderAddSearch(value: string) {
    if (!day) return;
    setReorderAddSearch(value);
    if (reorderAddTimerRef.current) clearTimeout(reorderAddTimerRef.current);
    const allIds = (day.exercises ?? []).map((e) => e.exercise_id).join(",");
    if (value.trim().length >= 2) {
      reorderAddTimerRef.current = setTimeout(async () => {
        setReorderAddLoading(true);
        try {
          const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?name=${encodeURIComponent(value.trim())}&exclude_ids=${allIds}`);
          setReorderAddAlternatives(data);
        } finally {
          setReorderAddLoading(false);
        }
      }, 300);
    } else if (value.trim().length === 0) {
      reorderAddTimerRef.current = setTimeout(async () => {
        setReorderAddLoading(true);
        try {
          const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?exclude_ids=${allIds}`);
          setReorderAddAlternatives(data);
        } finally {
          setReorderAddLoading(false);
        }
      }, 300);
    }
  }

  async function doAddDuring(exerciseId: number) {
    if (!day) return;
    setReorderAddDupeMsg(null);
    try {
      const created = await api.post<WorkoutDayExercise>(`/api/v1/workout_days/${day.id}/exercises`, { exercise_id: exerciseId });
      setDay((prev) => prev ? { ...prev, exercises: [...(prev.exercises ?? []), created] } : prev);
      setExerciseRuntime((prev) => ({ ...prev, [created.workout_day_exercise_id]: createRuntime(created) }));
      setShowReorderAdd(false);
      setReorderAddSearch("");
    } catch {
      setReorderAddDupeMsg("Exercício já está no treino.");
    }
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
    saveRestEnd(null);
    setRestAlert(false);
    setPhase("exercising");
  }

  if (loading || redirecting) return <LoadingScreen />;

  if (!plan?.days?.length && !day) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-[#0a0f1e] px-4 text-center">
        <h1 className="text-2xl font-bold text-white">Nenhum treino disponível</h1>
        <p className="mt-2 text-sm text-slate-400">Crie um planejamento para começar.</p>
        <button onClick={() => router.push("/plan")} className="mt-6 rounded-full bg-primary-500 px-6 py-3 text-sm font-semibold text-white">
          Ver planejamento
        </button>
      </div>
    );
  }

  if (phase === "choose") {
    return <ChooseScreen plan={plan!} sessions={sessions} onChoose={chooseWorkout} onToggleFavorite={toggleFavoriteWorkoutDay} onBack={() => router.push("/dashboard")} />;
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
              createRuntime(exercise, historyWeight(exercise)),
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
    return <CooldownScreen day={day!} onFinish={() => setPhase("closing_optional")} />;
  }

  if (phase === "closing_optional") {
    const allExs = day!.exercises ?? [];
    const hasCardioAlready = allExs.some(ex => isCardio(ex));
    const hasCoreAlready = allExs.some(ex => ex.muscle_group === "core");
    return (
      <ClosingOptionalScreen
        hasCardioAlready={hasCardioAlready}
        hasCoreAlready={hasCoreAlready}
        onFinish={() => setPhase("pre_done")}
        onExtraCardio={(data) => { setExtraBlockType("cardio"); setExtraBlockData(data); setPhase("pre_done"); }}
        onExtraAbs={(data) => { setExtraBlockType("abs"); setExtraBlockData(data); setPhase("pre_done"); }}
      />
    );
  }

  if (phase === "pre_done") {
    return (
      <PreDoneScreen
        day={day!}
        exerciseRuntime={exerciseRuntime}
        onFinish={() => setPhase("done")}
        onAddExercise={() => setPhase("overview")}
      />
    );
  }

  if (phase === "done") {
    return <DoneScreen day={day!} startTime={startTime ?? new Date()} runtime={exerciseRuntime} onSaved={endSession} lastStartedIndex={currentIndex} extraBlockType={extraBlockType} extraBlockData={extraBlockData} />;
  }

  const exercises = day!.exercises ?? [];
  const exercise = exercises[currentIndex];
  const runtime = runtimeFor(exerciseRuntime, exercise);

  if (!exercise) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-[#0a0f1e] px-4 text-center">
        <p className="mt-4 text-slate-400">Nenhum exercício encontrado para este treino.</p>
        <button onClick={() => setPhase("overview")} className="mt-4 text-sm text-primary-600 hover:underline">
          Voltar
        </button>
      </div>
    );
  }

  if (phase === "rest") {
    const isUrgent = restLeft <= 10;
    const strokeColor = isUrgent ? "#f97316" : "#22c55e";
    const radius = 80;
    const circumference = 2 * Math.PI * radius;
    const progress = restTotal > 0 ? restLeft / restTotal : 0;
    const dashOffset = circumference * (1 - progress);

    return (
      <div style={{ display: "flex", minHeight: "100svh", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "0 20px", background: "var(--bg)" }}>
        <p style={{ fontSize: 12, fontWeight: 700, fontVariantNumeric: "tabular-nums", color: "var(--primary)", background: "var(--primary-soft)", padding: "6px 14px", borderRadius: "var(--r-pill)", marginBottom: 32 }}>
          ⏱ {formatElapsed(elapsedSeconds)}
        </p>

        <AnimatePresence mode="wait">
          {restAlert ? (
            <motion.div
              key="alert"
              initial={{ scale: 0.7, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              className="flex flex-col items-center"
            >
              <motion.p
                animate={{ scale: [1, 1.06, 1] }}
                transition={{ duration: 0.6, repeat: Infinity }}
                className="text-4xl font-bold text-primary-500"
              >
                Hora de treinar!
              </motion.p>
              <p className="mt-2 text-3xl">💪</p>
            </motion.div>
          ) : (
            <motion.div key="timer" initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
              <p className="eyebrow" style={{ marginBottom: 24 }}>Descanso</p>

              <div className="rest-ring">
                <svg width="200" height="200" style={{ transform: "rotate(-90deg)" }}>
                  <circle cx="100" cy="100" r={radius} fill="none" stroke="var(--border)" strokeWidth="8" />
                  <motion.circle
                    cx="100" cy="100" r={radius}
                    fill="none"
                    stroke={isUrgent ? "var(--hot)" : "var(--primary)"}
                    strokeWidth="8"
                    strokeLinecap="round"
                    strokeDasharray={circumference}
                    animate={{ strokeDashoffset: dashOffset }}
                    transition={{ duration: 0.9, ease: "easeOut" }}
                    style={{ filter: isUrgent ? "drop-shadow(0 0 8px oklch(0.70 0.19 28))" : "drop-shadow(0 0 8px oklch(0.685 0.17 258))" }}
                  />
                </svg>
                <p className={`rest-timer ${isUrgent ? "alert" : ""}`}>{restLeft}s</p>
              </div>

              {/* AI tip */}
              {(() => {
                const rt = runtimeFor(exerciseRuntime, exercise);
                const isLastEx = currentIndex === (day!.exercises?.length ?? 1) - 1;
                return (
                  <div style={{ marginTop: 20, display: "flex", alignItems: "flex-start", gap: 12, maxWidth: 320 }}>
                    <AgentOrb size="card" glyph />
                    <AITrainerBubble
                      message={getRestMessage({
                        exerciseName: exercise.name,
                        muscleGroup: exercise.muscle_group,
                        isLastExercise: isLastEx,
                        isWarmup: rt.warmup_by_set?.[currentSet - 1],
                      })}
                      mood="speaking"
                      show
                      side="left"
                    />
                  </div>
                );
              })()}

              <PressButton
                onClick={skipRest}
                style={{ marginTop: 24, border: "1px solid var(--border)", borderRadius: "var(--r-md)", padding: "12px 24px", fontSize: 14, fontWeight: 600, color: "var(--text-muted)", background: "var(--surface)", cursor: "pointer" }}
              >
                Pular descanso
              </PressButton>
              <button onClick={() => setPhase("done")} style={{ marginTop: 12, fontSize: 13, fontWeight: 600, color: "var(--hot)", background: "none", border: 0, cursor: "pointer" }}>
                Encerrar treino agora
              </button>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    );
  }

  if (phase === "exercise_feedback") {
    const nextFeedbackEx = exercises[currentIndex + 1];
    const feedbackExercisesLeft = exercises.length - currentIndex - 1;
    return (
      <div className="flex min-h-svh flex-col bg-[#0a0f1e] px-4 pt-6" style={{ paddingBottom: "var(--nav-pb)" }}>
        <div className="flex flex-1 flex-col justify-center">
          <div className="flex items-center gap-2 mb-1">
            <p className="text-sm font-semibold uppercase tracking-wide text-primary-500">Exercício concluído</p>
            <span className="text-xs text-slate-500">{currentIndex + 1}/{exercises.length}</span>
          </div>
          <h1 className="mt-2 text-3xl font-bold text-white">{exercise.name}</h1>
          {nextFeedbackEx ? (
            <p className="mt-2 text-sm text-slate-400">
              Próximo: <span className="text-white font-semibold">{nextFeedbackEx.name}</span>
              {feedbackExercisesLeft > 1 && <span className="text-slate-500"> (+{feedbackExercisesLeft - 1} depois)</span>}
            </p>
          ) : (
            <p className="mt-2 text-sm text-primary-400 font-semibold">Último exercício do treino!</p>
          )}
          <p className="mt-3 text-slate-400">Como você se sentiu nesse exercício?</p>
          <div className="mt-6 grid grid-cols-2 gap-3">
            {FEELINGS.map((feeling) => (
              <button
                key={feeling.value}
                onClick={() => finishExercise(feeling.value)}
                className="rounded-xl border border-slate-700 bg-slate-900 px-4 py-4 text-sm font-semibold text-slate-300 hover:border-primary-400"
              >
                {feeling.label}
              </button>
            ))}
          </div>
        </div>
        <button onClick={() => finishExercise("nao_informado")} className="w-full py-3 text-sm text-slate-500">
          Pular
        </button>
      </div>
    );
  }

  const historicalMaxWeight = getHistoricalMaxWeight(sessions, exercise.exercise_id);
  const currentWeightNum = Number(runtime.weight_by_set[currentSet - 1]) || 0;
  const isCurrentSetWarmup = runtime.warmup_by_set?.[currentSet - 1] ?? false;
  const isNewPR = !isCardio(exercise) && !isTimed(exercise) && !isCurrentSetWarmup && currentWeightNum > 0 && historicalMaxWeight > 0 && currentWeightNum > historicalMaxWeight;
  const totalPlannedSets = exercises.reduce((sum, ex) => {
    if (isCardio(ex) || isTimed(ex)) return sum + 1;
    return sum + runtimeFor(exerciseRuntime, ex).planned_sets;
  }, 0);
  const completedSets = exercises.reduce((sum, ex, idx) => {
    const state = runtimeFor(exerciseRuntime, ex);
    const isTimedOrCardio = isCardio(ex) || isTimed(ex);
    if (idx < currentIndex) return sum + (isTimedOrCardio ? 1 : state.planned_sets);
    if (idx === currentIndex && !isTimedOrCardio) return sum + Math.max(0, currentSet - 1);
    return sum;
  }, 0);
  const setProgress = totalPlannedSets > 0 ? Math.min(100, Math.round((completedSets / totalPlannedSets) * 100)) : 0;
  const exerciseMediaUrl = getGymSafeImageUrl(exercise);

  return (
    <>
    <div style={{ display: "flex", height: "100svh", flexDirection: "column", overflow: "hidden", background: "var(--bg)", color: "var(--text)" }}>
      {/* Sticky header */}
      <div style={{ position: "sticky", top: 0, zIndex: 20, background: "var(--bg-2)", borderBottom: "1px solid var(--border)", backdropFilter: "blur(16px)", padding: "12px 16px 10px" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span style={{ fontSize: 13, fontWeight: 700, color: "var(--text-muted)" }}>
              Ex. {currentIndex + 1}/{exercises.length}
            </span>
            <span style={{ fontSize: 12, color: "var(--text-dim)" }}>·</span>
            <span style={{ fontSize: 13, fontWeight: 700, color: "var(--text-muted)" }}>
              S. {currentSet}/{runtimeFor(exerciseRuntime, exercise).planned_sets}
            </span>
            <button
              onClick={() => setShowReorderModal(true)}
              style={{ fontSize: 13, color: "var(--text-dim)", background: "none", border: 0, cursor: "pointer" }}
              aria-label="Reordenar exercícios"
            >
              ⇅
            </button>
          </div>
          <span style={{ fontSize: 13, fontWeight: 700, fontVariantNumeric: "tabular-nums", color: "var(--primary)", background: "var(--primary-soft)", padding: "6px 12px", borderRadius: "var(--r-pill)" }}>
            ⏱ {formatElapsed(elapsedSeconds)}
          </span>
          <button onClick={() => setPhase("done")} style={{ fontSize: 13, fontWeight: 700, color: "var(--hot)", background: "none", border: 0, cursor: "pointer" }}>Encerrar</button>
        </div>
        <div style={{ marginTop: 8, display: "flex", alignItems: "center", gap: 10 }}>
          <div className="exec-bar" style={{ flex: 1 }}>
            <motion.div
              className="exec-bar-fill"
              animate={{ width: `${setProgress}%` }}
              transition={{ duration: 0.4, ease: "easeOut" }}
            />
          </div>
          <p style={{ flexShrink: 0, fontSize: 12, fontWeight: 700, fontVariantNumeric: "tabular-nums", color: "var(--text-dim)" }}>
            {completedSets}/{totalPlannedSets}
          </p>
          {sessionVolume > 0 && (
            <p style={{ flexShrink: 0, fontSize: 12, fontWeight: 700, fontVariantNumeric: "tabular-nums", color: "var(--text-dim)" }}>
              <AnimatedCounter value={sessionVolume} />kg
            </p>
          )}
        </div>
      </div>

      <div className="flex flex-1 flex-col overflow-y-auto px-4 pt-4 min-h-0">
      <AnimatePresence mode="wait">
      <motion.div
        key={currentIndex}
        initial={{ opacity: 0, x: 28 }}
        animate={{ opacity: 1, x: 0 }}
        exit={{ opacity: 0, x: -28 }}
        transition={{ duration: 0.18, ease: "easeOut" }}
        className="flex flex-1 flex-col"
      >
        {/* Exercise media — large GIF when available */}
        {exerciseMediaUrl ? (
          <div
            className="relative w-full cursor-pointer overflow-hidden rounded-2xl"
            style={{ maxHeight: "clamp(160px, 38svh, 280px)" }}
            onClick={() => setGifModalExercise(exercise)}
          >
            <img
              src={exerciseMediaUrl}
              alt={exercise.name}
              className="w-full object-cover rounded-2xl"
              style={{ height: "clamp(160px, 38svh, 280px)" }}
            />
            <div className="absolute inset-0 flex items-end justify-between rounded-2xl bg-gradient-to-t from-black/60 via-transparent to-transparent px-3 pb-3">
              {exercise.muscle_group && (
                <span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${MUSCLE_COLORS[exercise.muscle_group] ?? "bg-gray-100 text-gray-600"}`}>
                  {exercise.muscle_group}
                </span>
              )}
              <span className="rounded-full bg-white/20 px-2.5 py-1 text-xs font-medium text-white backdrop-blur-sm">
                ▶ Ver completo
              </span>
            </div>
          </div>
        ) : (
          <div className="grid grid-cols-[1fr_96px] gap-2">
            <SmartImage
              src={getGymSafeImageUrl(exercise) ?? exerciseFallback(exercise)}
              fallbackSrc={exerciseFallback(exercise)}
              alt={exercise.name}
              className="h-44 w-full rounded-2xl object-cover"
            />
            <SmartImage
              src={exercise.muscle_image_url}
              fallbackSrc="/muscle-images/cardio.svg"
              alt={exercise.muscle_group ?? "músculo"}
              className="h-44 w-full rounded-2xl object-cover"
            />
          </div>
        )}

        {/* Action chips — Lumen style */}
        <div className="exec-actions" style={{ marginTop: 8 }}>
          {!exercise.gif_url && exerciseMediaUrl && (
            <button onClick={() => setGifModalExercise(exercise)} className="exec-chip">
              <svg viewBox="0 0 24 24"><polygon points="5 3 19 12 5 21 5 3"/></svg>
              Ver
            </button>
          )}
          <button onClick={() => setInfoModalExercise(exercise)} className="exec-chip">
            <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
            Info
          </button>
          <button
            onClick={() => setShowSwapChoice(true)}
            className="exec-chip warn"
          >
            <svg viewBox="0 0 24 24"><path d="M7 16V4m0 0L3 8m4-4l4 4"/><path d="M17 8v12m0 0l4-4m-4 4l-4-4"/></svg>
            Trocar
          </button>
        </div>

        {/* Exercise name */}
        <div className="mt-2">
          <h2 className="text-2xl font-bold text-white leading-tight">{exercise.name}</h2>
        </div>
        {(() => {
          // Server-computed via ExerciseHistoryService: it already excludes the
          // current in-progress session and any cancelled/abandoned ones, so
          // this never shows "done today" while the set below is still pending.
          const label = exercise.last_execution_label;
          if (!label || label === "Primeira vez neste exercício") {
            return <p className="mt-1 text-xs text-slate-500">Primeira vez neste exercício</p>;
          }
          const weight = exercise.last_weight_kg != null ? Number(exercise.last_weight_kg) : null;
          return (
            <div className="mt-2 rounded-lg border border-slate-700/60 bg-slate-800/50 px-3 py-2">
              <p className="text-xs font-medium text-slate-400 mb-1">{label}</p>
              {weight != null && weight > 0 && (
                <span className="text-sm font-bold text-white">{weight} kg</span>
              )}
              {exercise.progression_reason && (
                <p className="mt-1 text-xs font-semibold" style={{ color: "var(--primary, #60a5fa)" }}>
                  💡 {exercise.progression_reason}
                </p>
              )}
            </div>
          );
        })()}
        {isTimed(exercise) ? (
          /* ── Recovery panel (mobilidade / yoga / isometria) ── */
          <RecoveryPanel
            exerciseName={exercise.name}
            nextName={exercises[currentIndex + 1]?.name ?? null}
            imageUrl={exercise.image_url}
            gifUrl={exercise.gif_url ?? null}
            instruction={exercise.instructions ?? null}
            elapsedSeconds={timedElapsed}
            targetSeconds={(exercise.duration_minutes ?? 1) * 60}
            running={timedRunning}
            onToggle={() => setTimedRunning((v) => !v)}
            onOpenMedia={() => setGifModalExercise(exercise)}
          />
        ) : isInterval(exercise) ? (
          /* ── Interval panel (HIIT / Funcional / Circuito) ── */
          <IntervalPanel
            exerciseName={exercise.name}
            nextName={exercises[currentIndex + 1]?.name ?? null}
            secondsLeft={cardioTimeLeft}
            totalSeconds={(runtime.duration_minutes ?? 20) * 60}
            blockIndex={currentIndex + 1}
            blockTotal={exercises.length}
          />
        ) : isCardio(exercise) ? (
          /* ── Cardio panel (Bike / Corrida / Caminhada / Cardio) ── */
          <CardioPanel
            exerciseName={exercise.name}
            nextName={exercises[currentIndex + 1]?.name ?? null}
            secondsLeft={cardioTimeLeft}
            totalSeconds={(runtime.duration_minutes ?? 20) * 60}
            intensity={runtime.intensity}
            durationMin={runtime.duration_minutes}
            blockIndex={currentIndex + 1}
            blockTotal={exercises.length}
          />
        ) : (
          /* ── Strength exercise panel ─────────────────────── */
          <>
            <div className="mt-4 grid grid-cols-3 gap-3">
              <AdjustBox label="séries" value={runtime.planned_sets} onMinus={() => changePlannedSets(exercise, runtime.planned_sets - 1)} onPlus={() => changePlannedSets(exercise, runtime.planned_sets + 1)} />
              <AdjustBox label={`reps série ${currentSet}`} value={runtime.reps_by_set[currentSet - 1] ?? exercise.reps} onMinus={() => updateCurrentSetReps(exercise, Math.max(1, (runtime.reps_by_set[currentSet - 1] ?? exercise.reps) - 1))} onPlus={() => updateCurrentSetReps(exercise, (runtime.reps_by_set[currentSet - 1] ?? exercise.reps) + 1)} />
              <Metric label="série atual" value={currentSet} highlight />
            </div>

            <div className="mt-3 grid grid-cols-2 gap-3">
              {/* Peso com +/- */}
              {(() => {
                const rawWeight = runtime.weight_by_set[currentSet - 1];
                const weightVal = rawWeight !== "" && rawWeight !== undefined ? Number(rawWeight) : 0;
                const weightStep = weightVal >= 60 ? 5 : weightVal >= 20 ? 2.5 : 1;
                const weightDisplay = weightVal > 0 ? `${weightVal} kg` : "— kg";
                return (
                  <div className={`rounded-xl p-3 text-center ${weightError ? "bg-red-950/30 ring-1 ring-red-500/60" : "bg-slate-900/60"}`}>
                    <div className="flex items-center justify-center gap-2">
                      <button
                        onClick={() => { setWeightError(false); updateCurrentSetWeight(exercise, String(Math.max(0, +(weightVal - weightStep).toFixed(2)))); }}
                        className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-900 text-lg font-bold text-slate-400"
                      >-</button>
                      <p className={`min-w-14 text-xl font-bold ${weightVal > 0 ? "text-white" : "text-slate-600"}`}>{weightDisplay}</p>
                      <button
                        onClick={() => { setWeightError(false); updateCurrentSetWeight(exercise, String(+(weightVal + weightStep).toFixed(2))); }}
                        className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-900 text-lg font-bold text-slate-400"
                      >+</button>
                    </div>
                    <p className="mt-1 text-xs text-slate-400">peso · +{weightStep} kg</p>
                    {weightError && <p className="mt-0.5 text-xs text-red-400">Informe o peso</p>}
                  </div>
                );
              })()}

              {/* Descanso com +/- */}
              {(() => {
                const restVal = runtime.rest_seconds ?? 60;
                const restStep = restVal < 60 ? 15 : 30;
                const restMin = Math.floor(restVal / 60);
                const restSec = restVal % 60;
                const restDisplay = restMin > 0 ? `${restMin}:${restSec.toString().padStart(2, "0")}` : `${restSec}s`;
                return (
                  <div className="rounded-xl bg-slate-900/60 p-3 text-center">
                    <div className="flex items-center justify-center gap-2">
                      <button
                        onClick={() => updateRuntime(exercise.workout_day_exercise_id, { rest_seconds: Math.max(0, restVal - restStep) })}
                        className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-900 text-lg font-bold text-slate-400"
                      >-</button>
                      <p className="min-w-12 text-xl font-bold text-white">{restDisplay}</p>
                      <button
                        onClick={() => updateRuntime(exercise.workout_day_exercise_id, { rest_seconds: restVal + restStep })}
                        className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-900 text-lg font-bold text-slate-400"
                      >+</button>
                    </div>
                    <p className="mt-1 text-xs text-slate-400">descanso · +{restStep}s</p>
                  </div>
                );
              })()}
            </div>

            {/* Warmup toggle for current set */}
            {(() => {
              const isWarmup = runtime.warmup_by_set?.[currentSet - 1] ?? false;
              return (
                <button
                  onClick={() => toggleWarmup(exercise, currentSet - 1)}
                  className={`mt-2 flex w-full items-center justify-center gap-2 rounded-xl border py-2.5 text-xs font-semibold transition-colors ${
                    isWarmup
                      ? "border-amber-600/50 bg-amber-900/30 text-amber-400"
                      : "border-slate-700 bg-slate-900 text-slate-500 hover:border-slate-600"
                  }`}
                >
                  🔥 {isWarmup ? "Série de aquecimento (não conta na evolução)" : "Marcar como aquecimento"}
                </button>
              );
            })()}
          </>
        )}

        {/* PR Badge */}
        <AnimatePresence>
          {isNewPR && (
            <motion.div
              initial={{ opacity: 0, scale: 0.8, y: 8 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.8 }}
              className="mt-3 flex items-center gap-2 rounded-xl border border-yellow-700/50 bg-yellow-950/30 px-4 py-2.5"
              style={{ boxShadow: "0 0 12px 2px rgba(234,179,8,0.25)" }}
            >
              <span className="text-lg">🏆</span>
              <div>
                <p className="text-sm font-bold text-yellow-700">Novo recorde pessoal!</p>
                <p className="text-xs text-yellow-600">{currentWeightNum}kg — anterior: {historicalMaxWeight}kg</p>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
      </AnimatePresence>
      </div>

      <div className="px-4" style={{ paddingTop: 8, paddingBottom: "max(24px, env(safe-area-inset-bottom))", flexShrink: 0 }}>
      {isTimed(exercise) ? (
        <PressButton
          onClick={() => {
            if (timedTimerRef.current) clearInterval(timedTimerRef.current);
            setTimedRunning(false);
            updateRuntime(exercise.workout_day_exercise_id, { elapsed_seconds: timedElapsed });
            setPhase("exercise_feedback");
          }}
          className="w-full rounded-2xl py-4 text-base font-semibold text-white"
          style={{ background: "var(--primary)" }}
        >
          Concluir — {Math.floor(timedElapsed / 60).toString().padStart(2, "0")}:{(timedElapsed % 60).toString().padStart(2, "0")}
        </PressButton>
      ) : isCardio(exercise) ? (
        <PressButton onClick={() => finishExercise("bem")} className="w-full rounded-2xl bg-orange-500 py-4 text-base font-semibold text-white">
          Concluir cardio
        </PressButton>
      ) : (
        <GlowPulse color="green" radius={16} className="w-full">
          <motion.button
            onClick={handleSetDone}
            animate={setFlash ? { boxShadow: "0 0 0 3px rgba(34,197,94,0.5)" } : { boxShadow: "0 0 0 0px rgba(34,197,94,0)" }}
            whileTap={{ scale: 0.97 }}
            transition={{ duration: 0.12 }}
            className="w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white"
          >
            Feito — série {currentSet}/{runtime.planned_sets}
          </motion.button>
        </GlowPulse>
      )}
      </div>
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
            src={getGymSafeImageUrl(gifModalExercise) ?? exerciseFallback(gifModalExercise)}
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
        allWorkoutExerciseIds={exercises.map(e => e.exercise_id)}
        onSwap={swapDuringExercise}
        onClose={() => setShowSwapModal(false)}
      />
    )}

    {showSwapChoice && (
      <div className="fixed inset-0 z-[60] flex items-end bg-black/60" onClick={() => setShowSwapChoice(false)}>
        <div className="w-full rounded-t-2xl bg-slate-900 px-4 pb-10 pt-4" onClick={(e) => e.stopPropagation()}>
          <div className="mb-3 mx-auto h-1 w-10 rounded-full bg-slate-700" />
          <h3 className="mb-4 text-base font-bold text-white">Como quer trocar?</h3>

          <button
            onClick={() => { setShowSwapChoice(false); setShowSwapModal(true); }}
            className="mb-3 flex w-full items-center gap-3 rounded-2xl border border-slate-700 bg-slate-800 px-4 py-4 text-left active:bg-slate-700"
          >
            <span className="text-2xl">🔍</span>
            <div>
              <p className="font-semibold text-white">Escolher por conta própria</p>
              <p className="text-xs text-slate-400">Buscar e filtrar exercícios manualmente</p>
            </div>
          </button>

          <button
            onClick={() => { setShowSwapChoice(false); open({ intent: "swap" }); }}
            className="flex w-full items-center gap-3 rounded-2xl border border-primary-800/40 bg-primary-950/40 px-4 py-4 text-left active:bg-primary-900/40"
          >
            <span className="text-2xl">✦</span>
            <div>
              <p className="font-semibold text-primary-300">Sugerir com Personal IA</p>
              <p className="text-xs text-slate-400">IA sugere alternativas baseadas no seu histórico</p>
            </div>
          </button>
        </div>
      </div>
    )}

    {showReorderModal && (
      <div className="fixed inset-0 z-50 flex items-end bg-black/50" onClick={() => setShowReorderModal(false)}>
        <div
          className="max-h-[80vh] w-full overflow-y-auto rounded-t-2xl bg-slate-900 px-4 pb-8 pt-4"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-slate-700" />
          <div className="flex items-center justify-between mt-2 mb-4">
            <h3 className="text-base font-bold text-white">Gerenciar treino</h3>
            <button onClick={() => setShowReorderModal(false)} className="text-sm text-slate-500 hover:text-slate-300">Fechar</button>
          </div>
          <div className="space-y-2">
            {exercises.map((ex, idx) => {
              const isCurrent = ex.workout_day_exercise_id === exercises[currentIndex]?.workout_day_exercise_id;
              const isDone = idx < currentIndex;
              return (
                <div
                  key={ex.workout_day_exercise_id}
                  className={`rounded-xl border p-3 ${isCurrent ? "border-primary-500/50 bg-primary-500/12" : isDone ? "border-slate-800 bg-slate-800/50 opacity-60" : "border-slate-800 bg-slate-900/60"}`}
                >
                  <div className="flex items-center gap-3">
                    <span className="w-5 shrink-0 text-center text-xs font-bold text-slate-500">
                      {isDone ? "✓" : idx + 1}
                    </span>
                    <p className="flex-1 min-w-0 truncate text-sm font-medium text-white">{ex.name}</p>
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        onClick={() => handleMoveExercising(ex.workout_day_exercise_id, "up")}
                        disabled={idx === 0}
                        className="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-700 text-xs text-slate-500 disabled:opacity-25 hover:bg-slate-800"
                      >↑</button>
                      <button
                        onClick={() => handleMoveExercising(ex.workout_day_exercise_id, "down")}
                        disabled={idx === exercises.length - 1}
                        className="flex h-7 w-7 items-center justify-center rounded-lg border border-slate-700 text-xs text-slate-500 disabled:opacity-25 hover:bg-slate-800"
                      >↓</button>
                    </div>
                  </div>
                  {!isDone && (
                    <div className="mt-2 flex items-center gap-3 pl-8">
                      {isCurrent && <span className="text-xs font-semibold text-primary-500">atual</span>}
                      {!isCurrent && (
                        <button
                          onClick={() => {
                            setCurrentIndex(idx);
                            setCurrentSet(1);
                            setPhase("exercising");
                            setShowReorderModal(false);
                          }}
                          className="text-xs font-semibold text-primary-500 hover:text-primary-400"
                        >
                          Começar por este
                        </button>
                      )}
                      <button
                        onClick={() => setReorderSwapTarget(ex)}
                        className="text-xs font-semibold text-blue-400 hover:text-blue-300"
                      >
                        Trocar
                      </button>
                      <button
                        onClick={() => removeExerciseDuring(ex.workout_day_exercise_id)}
                        disabled={exercises.length <= 1}
                        className="flex h-6 w-6 items-center justify-center rounded-lg border border-slate-700 text-xs text-red-400 disabled:opacity-25 hover:bg-slate-800"
                      >✕</button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
          <div className="mt-4 border-t border-slate-800 pt-3">
            <button
              onClick={openReorderAdd}
              className="flex w-full items-center justify-center gap-2 rounded-xl border border-dashed border-primary-500/50 py-3 text-sm font-semibold text-primary-400"
            >
              + Adicionar exercício
            </button>
          </div>
        </div>
      </div>
    )}

    {reorderSwapTarget && (
      <div className="fixed inset-0 z-[60]">
        <SwapModal
          exercise={reorderSwapTarget}
          allWorkoutExerciseIds={exercises.map((e) => e.exercise_id)}
          onSwap={swapFromReorder}
          onClose={() => setReorderSwapTarget(null)}
        />
      </div>
    )}

    {showReorderAdd && (() => {
      const muscleGroups = Array.from(new Set(reorderAddAlternatives.filter((e) => e.muscle_group).map((e) => e.muscle_group as string)));
      const filtered = reorderAddAlternatives.filter((ex) => !reorderAddMuscleFilter || ex.muscle_group === reorderAddMuscleFilter);
      return (
        <div
          className="fixed inset-0 z-[60] flex items-end bg-black/50"
          onClick={() => { setShowReorderAdd(false); setReorderAddSearch(""); }}
        >
          <div
            className="flex max-h-[88vh] w-full flex-col rounded-t-2xl bg-slate-900"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex-shrink-0 px-4 pt-3 pb-2">
              <div className="mb-3 mx-auto h-1 w-10 rounded-full bg-slate-700" />
              <div className="flex items-center justify-between">
                <h3 className="text-base font-bold text-white">Adicionar exercício</h3>
                <button
                  onClick={() => { setShowReorderAdd(false); setReorderAddSearch(""); }}
                  className="text-slate-400 text-lg leading-none"
                >✕</button>
              </div>
            </div>
            <div className="flex-shrink-0 px-4 pb-2">
              <input
                type="text"
                placeholder="Buscar por nome..."
                value={reorderAddSearch}
                onChange={(e) => handleReorderAddSearch(e.target.value)}
                className="w-full rounded-xl border border-slate-700 bg-slate-800 px-4 py-2.5 text-sm text-white placeholder-slate-500 focus:border-primary-500 focus:outline-none"
              />
            </div>
            <div className="flex-shrink-0 overflow-x-auto px-4 pb-2">
              <div className="flex gap-2 min-w-max">
                {muscleGroups.map((mg) => (
                  <button
                    key={mg}
                    onClick={() => setReorderAddMuscleFilter((f) => f === mg ? null : mg)}
                    className={`rounded-full px-3 py-1.5 text-xs font-semibold transition-colors border ${reorderAddMuscleFilter === mg ? "bg-primary-500/20 text-primary-300 border-primary-500/40" : "bg-slate-800 text-slate-400 border-slate-700"}`}
                  >
                    {MUSCLE_LABELS[mg] ?? mg}
                  </button>
                ))}
              </div>
            </div>
            {reorderAddDupeMsg && (
              <p className="flex-shrink-0 mx-4 mb-2 rounded-lg bg-yellow-900/40 border border-yellow-700/40 px-3 py-2 text-xs text-yellow-400">
                {reorderAddDupeMsg}
              </p>
            )}
            <div className="flex-1 overflow-y-auto px-4 pb-8">
              {reorderAddLoading ? (
                <p className="p-4 text-center text-sm text-slate-500">Buscando...</p>
              ) : filtered.length === 0 ? (
                <p className="p-4 text-sm text-slate-400">Nenhum exercício encontrado.</p>
              ) : (
                filtered.map((alt) => (
                  <button
                    key={alt.id}
                    onClick={() => doAddDuring(alt.id)}
                    className="mb-2 flex w-full items-center gap-3 rounded-xl border border-slate-800 bg-slate-800/60 p-3 text-left active:bg-slate-700"
                  >
                    <SmartImage
                      src={getGymSafeImageUrl(alt) ?? exerciseFallback(alt)}
                      fallbackSrc={exerciseFallback(alt)}
                      alt={alt.name}
                      className="h-14 w-14 flex-shrink-0 rounded-lg object-cover"
                    />
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-medium text-white">{alt.name}</p>
                      {alt.muscle_group && (
                        <span className={`mt-1 inline-block rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[alt.muscle_group] ?? "bg-slate-700 text-slate-300"}`}>
                          {MUSCLE_LABELS[alt.muscle_group] ?? alt.muscle_group}
                        </span>
                      )}
                    </div>
                    <span className="flex-shrink-0 flex h-6 w-6 items-center justify-center rounded-full bg-primary-500/20 text-primary-400 text-sm font-bold">+</span>
                  </button>
                ))
              )}
            </div>
          </div>
        </div>
      );
    })()}
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

function lastSessionForDay(sessions: WorkoutSession[], dayId: number): WorkoutSession | null {
  return sessions
    .filter((s) => s.workout_day_id === dayId)
    .sort((a, b) => new Date(b.completed_at).getTime() - new Date(a.completed_at).getTime())[0] ?? null;
}

// relativeDate is imported from @/shared/utils/relative-date

function ChooseScreen({
  plan,
  sessions,
  onChoose,
  onToggleFavorite,
  onBack,
}: {
  plan: WorkoutPlan;
  sessions: WorkoutSession[];
  onChoose: (day: WorkoutDay) => void;
  onToggleFavorite: (dayId: number) => void;
  onBack: () => void;
}) {
  const recommendedId = recommendedDayId(plan, sessions);
  const router = useRouter();
  const [filter, setFilter] = useState<"all" | "favorites">("all");

  const favoriteDays = plan.days.filter((d) => d.favorited);
  const displayedDays = filter === "favorites" ? favoriteDays : plan.days;

  return (
    <div className="min-h-screen bg-[#0a0f1e] px-4 pt-6" style={{ paddingBottom: "var(--nav-pb)" }}>
      <div className="mb-4 flex items-center justify-between">
        <button onClick={onBack} className="text-sm text-slate-400">← Voltar</button>
        <button
          onClick={() => router.push("/dashboard")}
          className="flex items-center gap-1.5 rounded-full bg-primary-50 px-3 py-1.5 text-xs font-semibold text-primary-600 hover:bg-primary-100"
        >
          ✨ Dicas IA
        </button>
      </div>
      <h1 className="text-2xl font-bold text-white">Escolha seu treino</h1>
      <p className="mt-1 text-sm text-slate-400">Faça A, B, C ou qualquer outro que fizer sentido hoje.</p>

      {/* Filter tabs */}
      <div className="mt-4 flex gap-2">
        <button
          onClick={() => setFilter("all")}
          className={`rounded-full px-4 py-1.5 text-sm font-semibold transition-colors ${filter === "all" ? "bg-primary-500 text-white" : "bg-slate-800 text-slate-500"}`}
        >
          Todos
        </button>
        <button
          onClick={() => setFilter("favorites")}
          className={`flex items-center gap-1.5 rounded-full px-4 py-1.5 text-sm font-semibold transition-colors ${filter === "favorites" ? "bg-red-500 text-white" : "bg-slate-800 text-slate-500"}`}
        >
          ❤️ Favoritos {favoriteDays.length > 0 && <span className="rounded-full bg-slate-900/30 px-1.5 text-xs">{favoriteDays.length}</span>}
        </button>
      </div>

      <div className="mt-4 space-y-3">
        {displayedDays.length === 0 ? (
          <p className="rounded-xl border border-slate-800 bg-slate-900/60 p-6 text-center text-sm text-slate-500 dark:border-gray-800 dark:bg-gray-900">
            Nenhum treino favoritado ainda.<br />Toque em ❤️ em qualquer treino para adicionar.
          </p>
        ) : (
          displayedDays.map((day, idx) => {
            const isRecommended = day.id === recommendedId;
            const lastSession = day.id !== null ? lastSessionForDay(sessions, day.id) : null;
            const originalIdx = plan.days.findIndex((d) => d.id === day.id);
            return (
              <div
                key={day.id}
                className={`w-full rounded-xl border p-4 transition ${isRecommended ? "border-primary-500/50 bg-primary-500/10" : "border-slate-800 bg-slate-900/60"}`}
              >
                <div className="flex items-center gap-3">
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary-50 font-bold text-primary-600 dark:bg-primary-950/40">
                    {LETTERS[originalIdx] ?? originalIdx + 1}
                  </span>
                  <button className="flex-1 text-left" onClick={() => onChoose(day)}>
                    <div className="flex items-center gap-2">
                      <p className="font-semibold text-white">{day.custom_name || day.name}</p>
                      {isRecommended && (
                        <span className="rounded-full bg-primary-500 px-2 py-0.5 text-xs font-semibold text-white">Hoje</span>
                      )}
                    </div>
                    <p className="text-xs text-slate-400">{day.exercise_count} exercícios</p>
                    {day.muscle_groups?.length ? (
                      <div className="mt-1 flex flex-wrap gap-1">
                        {day.muscle_groups.slice(0, 2).map((m) => (
                          <span key={m} className={`rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[m] ?? "bg-gray-100 text-slate-400"}`}>{m}</span>
                        ))}
                      </div>
                    ) : null}
                    <p className="mt-0.5 text-xs text-slate-500">
                      {lastSession ? relativeDate(lastSession.completed_at) : "nunca executado"}
                    </p>
                  </button>
                  <button
                    onClick={(e) => { e.stopPropagation(); day.id !== null && onToggleFavorite(day.id); }}
                    className="shrink-0 p-1 text-xl leading-none transition-transform active:scale-90"
                    aria-label={day.favorited ? "Remover dos favoritos" : "Adicionar aos favoritos"}
                  >
                    {day.favorited ? "❤️" : "🤍"}
                  </button>
                </div>
              </div>
            );
          })
        )}
      </div>

      <section className="mt-8">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-400">Últimos 7 dias</h2>
        {sessions.length === 0 ? (
          <p className="mt-3 rounded-xl border border-slate-800 bg-slate-900 p-4 text-sm text-slate-400">Nenhum treino registrado nesse período.</p>
        ) : (
          <div className="mt-3 space-y-2">
            {sessions.map((session) => (
              <div key={session.id} className="rounded-xl border border-slate-800 bg-slate-900 p-4">
                <p className="font-medium text-white">{session.workout_day_name}</p>
                <p className="text-xs text-slate-400">
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
  const [addMuscleFilter, setAddMuscleFilter] = useState<string | null>(null);
  const [addFavoritesOnly, setAddFavoritesOnly] = useState(false);
  const [addDupeMsg, setAddDupeMsg] = useState<string | null>(null);
  const [infoModal, setInfoModal] = useState<WorkoutDayExercise | null>(null);
  const [gifModal, setGifModal] = useState<WorkoutDayExercise | null>(null);
  const [loadSuggestions, setLoadSuggestions] = useState<Record<number, { action: string; suggested_weight: number | null; reason: string } | "loading">>({});
  const exercises = day.exercises ?? [];
  const [globalRest, setGlobalRest] = useState<number>(exercises[0]?.rest_seconds ?? 90);
  const addSearchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Server-computed (filters in_progress/cancelled sessions) - no artificial
  // 7-day window like scanning the local `sessions` list would impose.
  const lastCompletedAt = day.last_completed_at ?? null;
  const recentSessionsCount = sessions.length;
  const plannedSetsCount = exercises.reduce((sum, exercise) => {
    if (isCardio(exercise) || isTimed(exercise)) return sum + 1;
    return sum + runtimeFor(runtime, exercise).planned_sets;
  }, 0);

  async function fetchLoadSuggestion(exerciseId: number) {
    if (loadSuggestions[exerciseId] !== undefined) return;
    setLoadSuggestions(prev => ({ ...prev, [exerciseId]: "loading" }));
    try {
      const data = await api.get<{ action: string; suggested_weight: number | null; reason: string }>(
        `/api/v1/workout_sessions/load_suggestion?exercise_id=${exerciseId}`
      );
      setLoadSuggestions(prev => ({ ...prev, [exerciseId]: data }));
    } catch {
      setLoadSuggestions(prev => ({ ...prev, [exerciseId]: { action: "maintain", suggested_weight: null, reason: "" } }));
    }
  }

  async function openAdd() {
    const allIds = exercises.map((e) => e.exercise_id).join(",");
    const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?exclude_ids=${allIds}`);
    setAddAlternatives(data);
    setAddMuscleFilter(null);
    setAddFavoritesOnly(false);
    setAddDupeMsg(null);
    setAddMode(true);
    setSwapMode(null);
  }

  function handleAddSearchChange(value: string) {
    setAddSearch(value);
    if (addSearchTimerRef.current) clearTimeout(addSearchTimerRef.current);
    const allIds = exercises.map((e) => e.exercise_id).join(",");
    if (value.trim().length >= 2) {
      addSearchTimerRef.current = setTimeout(async () => {
        setAddLoading(true);
        try {
          const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?name=${encodeURIComponent(value.trim())}&exclude_ids=${allIds}`);
          setAddAlternatives(data);
        } finally {
          setAddLoading(false);
        }
      }, 300);
    } else if (value.trim().length === 0) {
      addSearchTimerRef.current = setTimeout(async () => {
        setAddLoading(true);
        try {
          const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?exclude_ids=${allIds}`);
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

  async function doSwap(wdeId: number, replacementId: number, force = false): Promise<void> {
    try {
      const updated = await api.post<WorkoutDayExercise>(`/api/v1/workout_day_exercises/${wdeId}/swap`, {
        replacement_exercise_id: replacementId,
        force,
      });
      onChangeDay({ ...day, exercises: exercises.map((e) => e.workout_day_exercise_id === wdeId ? updated : e) });
      setSwapMode(null);
    } catch (err: unknown) {
      const body = (err as { body?: { error_code?: string; can_force?: boolean } })?.body;
      if (body?.error_code === "muscle_group_mismatch" && body?.can_force) {
        if (confirm("O exercício é de grupo muscular diferente. Deseja substituir mesmo assim?")) {
          await doSwap(wdeId, replacementId, true);
        }
      }
      // For other errors (duplicate etc), let them propagate to SwapModal's error handler
      else throw err;
    }
  }

  async function doAdd(exerciseId: number) {
    setAddDupeMsg(null);
    try {
      const created = await api.post<WorkoutDayExercise>(`/api/v1/workout_days/${day.id}/exercises`, { exercise_id: exerciseId });
      onChangeDay({ ...day, exercises: [...exercises, created] });
      setAddMode(false);
      setAddSearch("");
    } catch {
      setAddDupeMsg("Exercício já está no treino.");
    }
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

  const overviewRouter = useRouter();

  return (
  <>
    <div className="flex min-h-screen flex-col bg-[#0a0f1e] px-4 pt-6" style={{ paddingBottom: "var(--nav-pb)" }}>
      <div className="mb-4 flex items-center justify-between">
        <button onClick={onBack} className="text-sm text-slate-400">← Escolher outro</button>
        <button
          onClick={() => overviewRouter.push("/dashboard")}
          className="flex items-center gap-1.5 rounded-full bg-primary-50 px-3 py-1.5 text-xs font-semibold text-primary-600 hover:bg-primary-100"
        >
          ✨ Dicas IA
        </button>
      </div>
      <h1 className="text-2xl font-bold text-white">{day.custom_name || day.name}</h1>
      <p className="mt-1 text-sm text-slate-400">{exercises.length} exercícios</p>

      {day.invalid_workout_reason && (
        <div className="mt-4 rounded-2xl border border-amber-600/40 bg-amber-950/30 p-4">
          <p className="text-sm font-semibold text-amber-400">⚠ Treino com exercícios desatualizados</p>
          <p className="mt-1 text-xs leading-relaxed text-slate-300">
            Seu treino usava exercícios que não fazem mais parte da biblioteca validada da EasyHealth.
            Para manter a qualidade das imagens e execução, gere um novo treino.
          </p>
        </div>
      )}

      <div className="mt-4 rounded-2xl border border-primary-500/30 bg-primary-500/10 p-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-sm font-semibold text-primary-200">
              {lastCompletedAt ? "Continue sua sequência" : "Primeiro registro deste treino"}
            </p>
            <p className="mt-1 text-xs leading-relaxed text-slate-300">
              {lastCompletedAt
                ? `Última vez ${relativeDate(lastCompletedAt)}. Repita ou ajuste as cargas para manter evolução.`
                : "Complete hoje para desbloquear histórico, volume e comparações na próxima sessão."}
            </p>
          </div>
          <div className="shrink-0 text-right">
            <p className="text-lg font-bold text-white">{plannedSetsCount}</p>
            <p className="text-[11px] font-medium text-slate-400">séries</p>
          </div>
        </div>
        <div className="mt-3 grid grid-cols-3 gap-2 text-center text-[11px] font-semibold text-slate-300">
          <span className="rounded-full bg-slate-950/50 px-2 py-1">{recentSessionsCount} recentes</span>
          <span className="rounded-full bg-slate-950/50 px-2 py-1">{globalRest}s descanso</span>
          <span className="rounded-full bg-slate-950/50 px-2 py-1">IA pronta</span>
        </div>
      </div>

      <div className="mt-4 flex items-center gap-3 rounded-xl border border-slate-800 bg-slate-900 px-4 py-3">
        <span className="flex-1 text-sm font-medium text-slate-300">Descanso entre séries</span>
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
          className="w-20 rounded-lg border border-slate-700 px-3 py-2 text-right text-sm focus:border-primary-500 focus:outline-none"
        />
        <span className="text-sm text-slate-500">s</span>
      </div>

      <div className="mt-4 space-y-3">
        {exercises.map((ex) => {
          const state = runtimeFor(runtime, ex);
          return (
            <div key={ex.workout_day_exercise_id} className="rounded-xl border border-slate-800 bg-slate-900 p-4">
              <div className="flex gap-3">
                <SmartImage src={getGymSafeImageUrl(ex) ?? exerciseFallback(ex)} fallbackSrc={exerciseFallback(ex)} alt={ex.name} className="h-16 w-20 rounded-lg object-cover" />
                <SmartImage src={ex.muscle_image_url} fallbackSrc="/muscle-images/cardio.svg" alt={ex.muscle_group ?? "músculo"} className="h-16 w-14 rounded-lg object-cover" />
                <div className="min-w-0 flex-1">
                  <p className="font-semibold text-white">{ex.name}</p>
                  <p className="text-xs text-slate-500">{state.planned_sets} séries · {ex.reps} reps</p>
                  {(() => {
                    if (!ex.last_execution_label || ex.last_execution_label === "Primeira vez neste exercício") {
                      return <p className="text-xs text-gray-300">Nunca feito</p>;
                    }
                    const weight = ex.last_weight_kg != null && Number(ex.last_weight_kg) > 0 ? ` · ${ex.last_weight_kg} kg` : "";
                    const suggestion = !isCardio(ex) && !isTimed(ex) ? loadSuggestions[ex.exercise_id] : undefined;
                    return (
                      <div>
                        <p className="text-xs text-gray-300">{ex.last_execution_label}{weight}</p>
                        {suggestion === undefined && !isCardio(ex) && !isTimed(ex) && (
                          <button onClick={() => fetchLoadSuggestion(ex.exercise_id)} className="mt-0.5 text-xs text-primary-400 hover:underline">
                            💡 Ver sugestão de carga
                          </button>
                        )}
                        {suggestion === "loading" && <p className="mt-0.5 text-xs text-slate-500">Calculando...</p>}
                        {suggestion && suggestion !== "loading" && suggestion.action && (
                          <p className={`mt-0.5 text-xs font-semibold ${suggestion.action === "increase" ? "text-green-400" : "text-slate-400"}`}>
                            {suggestion.action === "increase" ? `↑ Teste ${suggestion.suggested_weight}kg hoje` : "→ Mantenha a carga"}
                          </p>
                        )}
                      </div>
                    );
                  })()}
                </div>
                <div className="flex flex-col items-end gap-1">
                  <button onClick={() => openSwap(ex)} className="text-xs text-blue-500 hover:underline">Trocar</button>
                  <div className="flex gap-1">
                    <button
                      onClick={() => handleMove(ex.workout_day_exercise_id, "up")}
                      disabled={exercises.indexOf(ex) === 0}
                      className="flex h-6 w-6 items-center justify-center rounded border border-slate-700 text-xs text-slate-500 disabled:opacity-25"
                    >↑</button>
                    <button
                      onClick={() => handleMove(ex.workout_day_exercise_id, "down")}
                      disabled={exercises.indexOf(ex) === exercises.length - 1}
                      className="flex h-6 w-6 items-center justify-center rounded border border-slate-700 text-xs text-slate-500 disabled:opacity-25"
                    >↓</button>
                  </div>
                </div>
              </div>
              <div className="mt-2 flex gap-2">
                {getGymSafeImageUrl(ex) && (
                  <button
                    onClick={() => setGifModal(ex)}
                    className="flex items-center gap-1 rounded-full border border-primary-200 bg-primary-50 px-2.5 py-1 text-xs font-semibold text-primary-600"
                  >
                    ▶ Ver vídeo
                  </button>
                )}
                <button
                  onClick={() => setInfoModal(ex)}
                  className="flex items-center gap-1 rounded-full border border-slate-700 bg-slate-900/60 px-2.5 py-1 text-xs font-semibold text-slate-400"
                >
                  ℹ Info
                </button>
              </div>
              {!isCardio(ex) && (
                <div className="mt-3">
                  <label className="block text-xs font-medium text-slate-400">
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
                      className="mt-1 w-28 rounded-lg border border-slate-700 px-3 py-2 text-sm focus:border-primary-500 focus:outline-none"
                    />
                  </label>
                </div>
              )}
            </div>
          );
        })}
      </div>

      <button onClick={openAdd} className="mt-4 w-full rounded-xl border border-dashed border-primary-500/50 py-3 text-sm font-semibold text-primary-400">Adicionar exercício</button>

      {swapMode && (
        <SwapModal
          exercise={swapMode}
          allWorkoutExerciseIds={exercises.map(e => e.exercise_id)}
          onSwap={doSwap}
          onClose={() => setSwapMode(null)}
        />
      )}

      {addMode && (() => {
        const muscleGroups = Array.from(new Set(addAlternatives.filter(e => e.muscle_group).map(e => e.muscle_group as string)));
        const filteredAdd = addAlternatives.filter(ex =>
          (!addFavoritesOnly || ex.is_favorite) &&
          (!addMuscleFilter || ex.muscle_group === addMuscleFilter)
        );
        return (
          <div className="fixed inset-0 z-50 flex items-end bg-black/50" onClick={() => { setAddMode(false); setAddSearch(""); }}>
            <div className="flex max-h-[88vh] w-full flex-col rounded-t-2xl bg-slate-900" onClick={(e) => e.stopPropagation()}>
              {/* Drag handle */}
              <div className="flex-shrink-0 px-4 pt-3 pb-2">
                <div className="mb-3 mx-auto h-1 w-10 rounded-full bg-slate-700" />
                <div className="flex items-center justify-between">
                  <h3 className="text-base font-bold text-white">Adicionar exercício</h3>
                  <button onClick={() => { setAddMode(false); setAddSearch(""); }} className="text-slate-400 text-lg leading-none">✕</button>
                </div>
              </div>

              {/* Search input */}
              <div className="flex-shrink-0 px-4 pb-2">
                <input
                  type="text"
                  placeholder="Buscar por nome..."
                  value={addSearch}
                  onChange={(e) => handleAddSearchChange(e.target.value)}
                  className="w-full rounded-xl border border-slate-700 bg-slate-800 px-4 py-2.5 text-sm text-white placeholder-slate-500 focus:border-primary-500 focus:outline-none"
                />
              </div>

              {/* Filter bar */}
              <div className="flex-shrink-0 overflow-x-auto px-4 pb-2">
                <div className="flex gap-2 min-w-max">
                  <button
                    onClick={() => setAddFavoritesOnly(f => !f)}
                    className={`flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold transition-colors ${addFavoritesOnly ? "bg-yellow-500/20 text-yellow-400 border border-yellow-500/40" : "bg-slate-800 text-slate-400 border border-slate-700"}`}
                  >
                    ⭐ Favoritos
                  </button>
                  {muscleGroups.map(mg => (
                    <button
                      key={mg}
                      onClick={() => setAddMuscleFilter(f => f === mg ? null : mg)}
                      className={`rounded-full px-3 py-1.5 text-xs font-semibold transition-colors border ${addMuscleFilter === mg ? "bg-primary-500/20 text-primary-300 border-primary-500/40" : "bg-slate-800 text-slate-400 border-slate-700"}`}
                    >
                      {MUSCLE_LABELS[mg] ?? mg}
                    </button>
                  ))}
                </div>
              </div>

              {/* Dupe warning */}
              {addDupeMsg && (
                <p className="flex-shrink-0 mx-4 mb-2 rounded-lg bg-yellow-900/40 border border-yellow-700/40 px-3 py-2 text-xs text-yellow-400">{addDupeMsg}</p>
              )}

              {/* Exercise list */}
              <div className="flex-1 overflow-y-auto px-4 pb-8">
                {addLoading ? (
                  <p className="p-4 text-center text-sm text-slate-500">Buscando...</p>
                ) : filteredAdd.length === 0 ? (
                  <p className="p-4 text-sm text-slate-400">Nenhum exercício encontrado.</p>
                ) : (
                  filteredAdd.map((alt) => (
                    <button
                      key={alt.id}
                      onClick={() => doAdd(alt.id)}
                      className="mb-2 flex w-full items-center gap-3 rounded-xl border border-slate-800 bg-slate-800/60 p-3 text-left active:bg-slate-700"
                    >
                      <SmartImage
                        src={getGymSafeImageUrl(alt) ?? exerciseFallback(alt)}
                        fallbackSrc={exerciseFallback(alt)}
                        alt={alt.name}
                        className="h-14 w-14 flex-shrink-0 rounded-lg object-cover"
                      />
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium text-white">{alt.name}</p>
                        <div className="mt-1 flex flex-wrap items-center gap-1.5">
                          {alt.muscle_group && (
                            <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[alt.muscle_group] ?? "bg-slate-700 text-slate-300"}`}>
                              {MUSCLE_LABELS[alt.muscle_group] ?? alt.muscle_group}
                            </span>
                          )}
                          {alt.equipment_type && alt.equipment_type !== "bodyweight" && (
                            <span className="text-xs text-slate-500 capitalize">{alt.equipment_type}</span>
                          )}
                        </div>
                      </div>
                      <div className="flex flex-shrink-0 flex-col items-end gap-1">
                        {alt.is_favorite && (
                          <svg viewBox="0 0 24 24" className="h-4 w-4 fill-yellow-400 stroke-yellow-400 stroke-[1.5]">
                            <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
                          </svg>
                        )}
                        <span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary-500/20 text-primary-400 text-sm font-bold">+</span>
                      </div>
                    </button>
                  ))
                )}
              </div>
            </div>
          </div>
        );
      })()}

      <button onClick={onStart} className="mt-auto w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white hover:bg-primary-600">Iniciar treino</button>
    </div>
    <ExerciseInfoModal exercise={infoModal} onClose={() => setInfoModal(null)} />

    {gifModal && (
      <div className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-black/90" onClick={() => setGifModal(null)}>
        <p className="mb-4 text-sm font-medium text-white/70">{gifModal.name}</p>
        {gifModal.video_url ? (
          <video src={gifModal.video_url} autoPlay loop muted playsInline className="max-h-[70vh] max-w-full rounded-xl object-contain" />
        ) : (
          <img src={getGymSafeImageUrl(gifModal) ?? exerciseFallback(gifModal)} alt={gifModal.name} className="max-h-[70vh] max-w-full rounded-xl object-contain" />
        )}
        <p className="mt-4 text-xs text-white/50">Toque para fechar</p>
      </div>
    )}
  </>
  );
}

// ─── PreDoneScreen ────────────────────────────────────────────────────────────

const CARDIO_TYPES = new Set(["cardio", "corrida", "bike", "caminhada", "hiit", "funcional"]);

function analyzeWorkout(day: WorkoutDay, runtime: Record<number, ExerciseRuntime>) {
  const exercises = day.exercises ?? [];
  const hasCore = exercises.some((e) => e.muscle_group === "core");
  const hasCardio = exercises.some((e) => CARDIO_TYPES.has(e.exercise_type));
  const totalSets = exercises.reduce((sum, e) => sum + (runtime[e.workout_day_exercise_id]?.planned_sets ?? 0), 0);
  return { hasCore, hasCardio, totalSets, count: exercises.length };
}

function PreDoneScreen({
  day,
  exerciseRuntime,
  onFinish,
  onAddExercise,
}: {
  day: WorkoutDay;
  exerciseRuntime: Record<number, ExerciseRuntime>;
  onFinish: () => void;
  onAddExercise: () => void;
}) {
  const { hasCore, hasCardio, totalSets, count } = analyzeWorkout(day, exerciseRuntime);

  const suggestions: { icon: string; label: string; detail: string; action: () => void }[] = [];
  if (!hasCore) {
    suggestions.push({
      icon: "🔥",
      label: "Adicionar core",
      detail: "Abdômen e estabilizadores não foram trabalhados hoje.",
      action: onAddExercise,
    });
  }
  if (!hasCardio) {
    suggestions.push({
      icon: "💨",
      label: "Fazer cardio",
      detail: "Inclua 10–15 min de cardio para queima adicional.",
      action: onAddExercise,
    });
  }

  return (
    <div
      style={{
        minHeight: "100dvh",
        background: "var(--bg)",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "24px 20px",
        gap: 0,
      }}
    >
      {/* Header */}
      <div style={{ textAlign: "center", marginBottom: 28 }}>
        <div style={{ fontSize: 48, marginBottom: 8 }}>💪</div>
        <h2 style={{ fontSize: 22, fontWeight: 800, margin: 0, color: "var(--text)" }}>
          Treino concluído!
        </h2>
        <p style={{ fontSize: 13, color: "var(--text-dim)", marginTop: 6 }}>
          {count} exercício{count !== 1 ? "s" : ""} · {totalSets} série{totalSets !== 1 ? "s" : ""}
        </p>
      </div>

      {/* Suggestions */}
      {suggestions.length > 0 && (
        <div
          style={{
            width: "100%",
            maxWidth: 380,
            marginBottom: 24,
            background: "var(--surface)",
            borderRadius: "var(--r-lg)",
            border: "1px solid var(--border)",
            padding: "16px",
          }}
        >
          <p style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.08em", color: "var(--text-dim)", textTransform: "uppercase", margin: "0 0 12px" }}>
            Sugestão do coach
          </p>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {suggestions.map((s) => (
              <button
                key={s.label}
                onClick={s.action}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 12,
                  background: "var(--primary-soft)",
                  border: "1px solid var(--primary-dim, oklch(0.4 0.1 258 / 0.3))",
                  borderRadius: "var(--r-md)",
                  padding: "12px 14px",
                  cursor: "pointer",
                  textAlign: "left",
                  width: "100%",
                }}
              >
                <span style={{ fontSize: 22, flexShrink: 0 }}>{s.icon}</span>
                <div>
                  <p style={{ fontSize: 14, fontWeight: 700, color: "var(--primary)", margin: 0 }}>{s.label}</p>
                  <p style={{ fontSize: 12, color: "var(--text-dim)", margin: "2px 0 0" }}>{s.detail}</p>
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* CTA */}
      <div style={{ width: "100%", maxWidth: 380, display: "flex", flexDirection: "column", gap: 10 }}>
        <button
          onClick={onFinish}
          style={{
            width: "100%",
            padding: "15px",
            borderRadius: "var(--r-full)",
            background: "var(--primary)",
            color: "#fff",
            fontSize: 15,
            fontWeight: 700,
            border: "none",
            cursor: "pointer",
          }}
        >
          Finalizar treino
        </button>
        {suggestions.length === 0 && (
          <button
            onClick={onAddExercise}
            style={{
              width: "100%",
              padding: "13px",
              borderRadius: "var(--r-full)",
              background: "transparent",
              color: "var(--text-dim)",
              fontSize: 14,
              fontWeight: 600,
              border: "1px solid var(--border)",
              cursor: "pointer",
            }}
          >
            Adicionar mais um exercício
          </button>
        )}
      </div>
    </div>
  );
}

function DoneScreen({
  day,
  startTime,
  runtime,
  onSaved,
  lastStartedIndex,
  extraBlockType,
  extraBlockData,
}: {
  day: WorkoutDay;
  startTime: Date;
  runtime: Record<number, ExerciseRuntime>;
  onSaved?: () => void;
  lastStartedIndex?: number;
  extraBlockType?: "cardio" | "abs" | null;
  extraBlockData?: Record<string, unknown> | null;
}) {
  const router = useRouter();
  const { user, updateUser } = useAuth();
  const [finishedAt] = useState(() => new Date());
  const duration = Math.max(1, Math.round((finishedAt.getTime() - startTime.getTime()) / 60000));
  const [fatigueLevel, setFatigueLevel] = useState(3);
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState("");
  const [showUpgrade, setShowUpgrade] = useState(false);
  const [savedCalories, setSavedCalories] = useState<number | null>(null);
  const [isSaved, setIsSaved] = useState(false);
  const [savedSessionId, setSavedSessionId] = useState<number | null>(null);
  const [savedFatigue, setSavedFatigue] = useState(3);
  const [savedNotes, setSavedNotes] = useState("");
  const [updateSuccess, setUpdateSuccess] = useState(false);
  const [updating, setUpdating] = useState(false);
  const [currentStreak, setCurrentStreak] = useState<number | null>(null);
  const [showProfiling, setShowProfiling] = useState(false);
  const exercises = useMemo(() => day.exercises ?? [], [day.exercises]);

  const completionData = useMemo(() => {
    const maxReached = lastStartedIndex ?? exercises.length - 1;
    let plannedSets = 0;
    let completedSets = 0;
    const skipped: Array<{ exercise_id: number; name: string; planned_sets: number; muscle_group: string | null }> = [];

    exercises.forEach((ex, idx) => {
      const state = runtimeFor(runtime, ex);
      const isCardioEx = isCardio(ex);
      const isTimedEx = isTimed(ex);

      if (isCardioEx || isTimedEx) {
        plannedSets += 1;
        const hasData = isTimedEx
          ? (state.elapsed_seconds ?? 0) > 0
          : (state.duration_minutes ?? 0) > 0;
        if (hasData) completedSets += 1;
        else if (idx > maxReached) skipped.push({ exercise_id: ex.exercise_id, name: ex.name, planned_sets: 1, muscle_group: ex.muscle_group });
        return;
      }

      const ps = state.planned_sets || ex.sets || 1;
      plannedSets += ps;

      if (idx > maxReached) {
        skipped.push({ exercise_id: ex.exercise_id, name: ex.name, planned_sets: ps, muscle_group: ex.muscle_group });
        return;
      }

      const doneCount = state.reps_by_set.filter((r, i) => r > 0 || Number(state.weight_by_set[i]) > 0).length;
      completedSets += Math.min(doneCount, ps);
      if (doneCount === 0) {
        skipped.push({ exercise_id: ex.exercise_id, name: ex.name, planned_sets: ps, muscle_group: ex.muscle_group });
      }
    });

    const rate = plannedSets > 0 ? Math.round((completedSets / plannedSets) * 100) : 100;
    const status = rate >= 100 ? "completed" : rate === 0 ? "abandoned" : "completed_partial";
    return { completionStatus: status, completionRate: rate, completedSetsCount: completedSets, plannedSetsCount: plannedSets, skippedExercises: skipped };
  }, [exercises, runtime, lastStartedIndex]);

  const totalVolume = useMemo(() => {
    let total = 0;
    exercises.forEach((ex) => {
      if (isCardio(ex) || isTimed(ex)) return;
      const state = runtimeFor(runtime, ex);
      state.weight_by_set.forEach((w, i) => {
        total += (Number(w) || 0) * (state.reps_by_set[i] || 0);
      });
    });
    return Math.round(total);
  }, [exercises, runtime]);

  const muscles = useMemo(
    () => [...new Set(exercises.map((e) => e.muscle_group).filter(Boolean) as string[])],
    [exercises],
  );

  // Auto-save on mount — no intermediate step needed
  useEffect(() => {
    async function save() {
      setSaving(true);
      try {
        const isQuick = day.quick === true;
        const saved = await api.post<WorkoutSession>("/api/v1/workout_sessions", {
          workout_day_id: isQuick ? null : day.id,
          source: isQuick ? "quick" : "plan",
          duration_minutes: duration,
          fatigue_level: fatigueLevel,
          notes: notes || null,
          completed_at: finishedAt.toISOString(),
          completion_status: completionData.completionStatus,
          completion_rate: completionData.completionRate,
          completed_sets_count: completionData.completedSetsCount,
          planned_sets_count: completionData.plannedSetsCount,
          skipped_exercises: completionData.skippedExercises,
          ...(extraBlockType ? {
            extra_block_type: extraBlockType,
            extra_block_data: extraBlockData ?? {},
            extra_started_at: finishedAt.toISOString(),
          } : {}),
          exercise_logs: exercises.map((exercise) => {
            const state = runtimeFor(runtime, exercise);
            const wdeId = isQuick || exercise.workout_day_exercise_id < 0 ? null : exercise.workout_day_exercise_id;
            if (isTimed(exercise)) {
              return {
                workout_day_exercise_id: wdeId,
                exercise_id: exercise.exercise_id,
                name: exercise.name,
                elapsed_seconds: state.elapsed_seconds ?? 0,
                target_seconds: (exercise.duration_minutes ?? 1) * 60,
                feeling: state.feeling || null,
              };
            }
            if (isCardio(exercise)) {
              return {
                workout_day_exercise_id: wdeId,
                exercise_id: exercise.exercise_id,
                name: exercise.name,
                duration_minutes: state.duration_minutes ?? exercise.duration_minutes ?? null,
                intensity: state.intensity ?? null,
                feeling: state.feeling || null,
              };
            }
            return {
              workout_day_exercise_id: wdeId,
              exercise_id: exercise.exercise_id,
              name: exercise.name,
              weight_kg: firstWeight(state.weight_by_set),
              weight_by_set: state.weight_by_set.map((value) => value ? Number(value) : null),
              is_warmup_by_set: state.warmup_by_set ?? [],
              planned_sets: exercise.sets,
              sets: state.planned_sets,
              reps: state.reps_by_set,
              rest_seconds: state.rest_seconds,
              feeling: state.feeling || null,
            };
          }),
        });
        trackEvent(EVENTS.WORKOUT_COMPLETED, {
          workout_day_id: day.id ?? undefined,
          workout_name: day.name,
          duration_minutes: duration,
          exercises_count: exercises.length,
          total_volume: totalVolume,
          source: isQuick ? "quick_workout" : "workout_today",
        });
        onSaved?.();
        setSavedCalories(saved.calories_estimated ?? null);
        setSavedSessionId(saved.id);
        setSavedFatigue(fatigueLevel);
        setSavedNotes(notes);
        setIsSaved(true);
        // Mark free workout as used in frontend state so UpgradeGate blocks next attempt
        if (user?.billing_status && !user.billing_status.paid) {
          updateUser({ billing_status: { ...user.billing_status, free_workout_used: true } });
        }
        // Signal dashboard to refetch fresh stats on next visit
        try { sessionStorage.setItem("dashboard_stale", "1"); } catch { /* ok */ }
        router.refresh();
        // Fetch updated streak to show in done screen
        api.get<{ streak: number }>("/api/v1/workout_sessions/stats").then((s) => {
          setCurrentStreak(s.streak);
        }).catch(() => { /* non-critical */ });
      } catch (e) {
        if (e instanceof ApiError && e.status === 403) {
          setShowUpgrade(true);
        } else {
          setSaveError("Erro ao salvar o treino. Tente novamente.");
        }
      } finally {
        setSaving(false);
      }
    }
    save();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function retrySave() {
    setSaving(true);
    setSaveError("");
    try {
      const isQuick = day.quick === true;
      const saved = await api.post<WorkoutSession>("/api/v1/workout_sessions", {
        workout_day_id: isQuick ? null : day.id,
        source: isQuick ? "quick" : "plan",
        duration_minutes: duration,
        fatigue_level: fatigueLevel,
        notes: notes || null,
        completed_at: finishedAt.toISOString(),
        exercise_logs: exercises.map((exercise) => {
          const state = runtimeFor(runtime, exercise);
          const wdeId = isQuick || exercise.workout_day_exercise_id < 0 ? null : exercise.workout_day_exercise_id;
          if (isTimed(exercise)) {
            return {
              workout_day_exercise_id: wdeId,
              exercise_id: exercise.exercise_id,
              name: exercise.name,
              elapsed_seconds: state.elapsed_seconds ?? 0,
              target_seconds: (exercise.duration_minutes ?? 1) * 60,
              feeling: state.feeling || null,
            };
          }
          if (isCardio(exercise)) {
            return {
              workout_day_exercise_id: wdeId,
              exercise_id: exercise.exercise_id,
              name: exercise.name,
              duration_minutes: state.duration_minutes ?? exercise.duration_minutes ?? null,
              intensity: state.intensity ?? null,
              feeling: state.feeling || null,
            };
          }
          return {
            workout_day_exercise_id: wdeId,
            exercise_id: exercise.exercise_id,
            name: exercise.name,
            weight_kg: firstWeight(state.weight_by_set),
            weight_by_set: state.weight_by_set.map((value) => value ? Number(value) : null),
            is_warmup_by_set: state.warmup_by_set ?? [],
            planned_sets: exercise.sets,
            sets: state.planned_sets,
            reps: state.reps_by_set,
            rest_seconds: state.rest_seconds,
            feeling: state.feeling || null,
          };
        }),
      });
      trackEvent(EVENTS.WORKOUT_COMPLETED, {
        workout_day_id: day.id ?? undefined,
        workout_name: day.name,
        duration_minutes: duration,
        exercises_count: exercises.length,
        total_volume: totalVolume,
        source: isQuick ? "quick_workout_retry" : "workout_today_retry",
      });
      onSaved?.();
      setSavedCalories(saved.calories_estimated ?? null);
      setSavedSessionId(saved.id);
      setSavedFatigue(fatigueLevel);
      setSavedNotes(notes);
      setIsSaved(true);
      if (user?.billing_status && !user.billing_status.paid) {
        updateUser({ billing_status: { ...user.billing_status, free_workout_used: true } });
      }
    } catch (e) {
      if (e instanceof ApiError && e.status === 403) {
        setShowUpgrade(true);
        setSaveError("");
      } else {
        setSaveError("Erro ao salvar. Tente novamente.");
      }
    } finally {
      setSaving(false);
    }
  }

  async function updateSession() {
    if (!savedSessionId) return;
    setUpdating(true);
    setUpdateSuccess(false);
    try {
      await api.patch(`/api/v1/workout_sessions/${savedSessionId}`, {
        fatigue_level: fatigueLevel,
        notes: notes || null,
      });
      setSavedFatigue(fatigueLevel);
      setSavedNotes(notes);
      setUpdateSuccess(true);
      setTimeout(() => setUpdateSuccess(false), 3000);
    } catch {
      // silent — user can retry
    } finally {
      setUpdating(false);
    }
  }

  const staggerContainer = {
    hidden: {},
    visible: { transition: { staggerChildren: 0.08 } },
  };
  const staggerItem = {
    hidden: { opacity: 0, y: 16 },
    visible: { opacity: 1, y: 0, transition: { duration: 0.3 } },
  };

  const calCols = savedCalories != null && savedCalories > 0 ? "grid-cols-2" : "grid-cols-3";

  return (
    <div className="flex min-h-svh flex-col bg-[#0a0f1e] px-4 pt-6" style={{ paddingBottom: "calc(var(--nav-pb) + 32px)" }}>
      <ConfettiBurst preset="workout" />

      <motion.div
        className="text-center"
        initial={{ opacity: 0, scale: 0.9 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.4, ease: "easeOut" }}
      >
        <div className="flex justify-center">
          <AITrainerAvatar mood="celebrating" size="lg" />
        </div>
        <h1 className="mt-2 text-2xl font-bold text-white">Treino concluído!</h1>
        <p className="mt-1 text-slate-400">{day.custom_name || day.name}</p>
        {saving && <p className="mt-2 text-xs text-primary-500">Salvando...</p>}
      </motion.div>

      {/* Metrics */}
      <motion.div
        className={`mt-6 grid gap-3 ${calCols}`}
        variants={staggerContainer}
        initial="hidden"
        animate="visible"
      >
        <motion.div variants={staggerItem} className="flex flex-col items-center rounded-2xl bg-primary-50 p-4">
          <p className="text-2xl font-bold text-primary-600"><AnimatedCounter value={duration} /></p>
          <p className="mt-0.5 text-xs text-primary-400">minutos</p>
        </motion.div>
        <motion.div variants={staggerItem} className="flex flex-col items-center rounded-2xl bg-green-50 p-4">
          <p className="text-2xl font-bold text-green-600">
            {totalVolume >= 1000
              ? <><AnimatedCounter value={totalVolume / 1000} format={(v) => v.toFixed(1)} />t</>
              : <><AnimatedCounter value={totalVolume} />kg</>
            }
          </p>
          <p className="mt-0.5 text-xs text-green-400">volume</p>
        </motion.div>
        <motion.div variants={staggerItem} className="flex flex-col items-center rounded-2xl bg-slate-900/60 p-4 dark:bg-gray-900">
          <p className="text-2xl font-bold text-slate-300 dark:text-gray-200"><AnimatedCounter value={exercises.length} /></p>
          <p className="mt-0.5 text-xs text-slate-500">exercícios</p>
        </motion.div>
        <AnimatePresence>
          {savedCalories != null && savedCalories > 0 && (
            <motion.div
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              className="flex flex-col items-center rounded-2xl bg-orange-50 p-4"
            >
              <p className="text-2xl font-bold text-orange-500">~<AnimatedCounter value={savedCalories} /></p>
              <p className="mt-0.5 text-xs text-orange-400">kcal est.</p>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>

      <motion.div
        className="mt-6 space-y-3"
        variants={staggerContainer}
        initial="hidden"
        animate="visible"
      >
        {/* Partial completion banner */}
        {completionData.completionStatus === "completed_partial" && (
          <motion.div variants={staggerItem} className="rounded-xl border border-orange-500/30 bg-orange-500/10 p-3">
            <p className="text-sm font-semibold text-orange-400">Treino parcial — {completionData.completionRate}% concluído</p>
            <p className="mt-0.5 text-xs text-slate-400">
              {completionData.completedSetsCount} de {completionData.plannedSetsCount} séries realizadas
            </p>
          </motion.div>
        )}

        {/* Exercise summary */}
        <motion.p variants={staggerItem} className="text-sm font-semibold text-slate-300 dark:text-gray-300">Resumo por exercício</motion.p>
        {exercises.map((exercise) => {
          const state = runtimeFor(runtime, exercise);
          const wasSkipped = completionData.skippedExercises.some(s => s.exercise_id === exercise.exercise_id);
          return (
            <motion.div variants={staggerItem} key={exercise.workout_day_exercise_id} className={`rounded-xl border p-3 ${wasSkipped ? "border-orange-900/50 bg-orange-950/30" : "border-slate-800 bg-slate-900 dark:border-gray-800 dark:bg-gray-900"}`}>
              <div className="flex items-center gap-2">
                <span className="text-xs">{wasSkipped ? "⚠️" : "✅"}</span>
                <span className="text-sm font-medium text-white">{exercise.name}</span>
              </div>
              {wasSkipped ? (
                <p className="mt-1 text-xs text-orange-400/70">Não realizado</p>
              ) : isCardio(exercise) ? (
                <p className="mt-1 text-xs text-slate-500">
                  Duração: {state.duration_minutes ?? exercise.duration_minutes ?? "—"} min
                  {state.intensity ? ` · ${state.intensity}` : ""}
                  {state.feeling ? ` · ${state.feeling}` : ""}
                </p>
              ) : (
                <p className="mt-1 text-xs text-slate-500">
                  Peso: {formatWeights(state.weight_by_set)} · Reps: {state.reps_by_set.join(", ")}
                  {state.feeling ? ` · ${state.feeling}` : ""}
                </p>
              )}
            </motion.div>
          );
        })}

        {/* Extra block summary */}
        {extraBlockType && extraBlockData && (
          <motion.div variants={staggerItem} className="rounded-xl border border-primary-500/30 bg-primary-500/10 p-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-primary-400 mb-1">Extra pós-treino</p>
            {extraBlockType === "cardio" && (
              <p className="text-sm text-white">
                {CARDIO_MODALITIES.find(m => m.key === (extraBlockData.modality as string))?.icon ?? "🚴"}{" "}
                {extraBlockData.modality as string} · {extraBlockData.duration_minutes as number} min · {extraBlockData.intensity as string}
              </p>
            )}
            {extraBlockType === "abs" && (
              <p className="text-sm text-white">
                Core · {(extraBlockData.exercises as string[]).join(", ")}
              </p>
            )}
          </motion.div>
        )}

        {/* Streak badge */}
        {currentStreak != null && currentStreak > 0 && (
          <motion.div
            variants={staggerItem}
            className="flex items-center justify-center gap-2 rounded-xl bg-orange-500/10 py-3 px-4 border border-orange-500/20"
          >
            <span className="text-xl">🔥</span>
            <span className="text-sm font-bold text-orange-400">
              Sequência atual: {currentStreak} {currentStreak === 1 ? "dia" : "dias"}
            </span>
          </motion.div>
        )}

        {/* Fatigue + notes */}
        <motion.div variants={staggerItem} className="rounded-xl border border-slate-800 bg-slate-900 p-4">
          <label className="text-sm font-semibold text-slate-300 dark:text-gray-300">Nível geral de cansaço</label>
          <div className="mt-3 flex gap-2">
            {[1, 2, 3, 4, 5].map((level) => (
              <button key={level} onClick={() => setFatigueLevel(level)} className={`h-10 flex-1 rounded-lg text-sm font-bold transition-colors ${fatigueLevel === level ? "bg-primary-500 text-white" : "bg-slate-800 text-slate-400 hover:bg-slate-700"}`}>
                {level}
              </button>
            ))}
          </div>
        </motion.div>

        <motion.div variants={staggerItem}>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Alguma anotação? (opcional)"
            rows={2}
            className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-slate-200 placeholder-slate-500 focus:border-primary-500 focus:outline-none dark:bg-gray-900"
          />
        </motion.div>

        {/* Save observations button — shown after initial auto-save when user changes fields */}
        {isSaved && savedSessionId && (fatigueLevel !== savedFatigue || notes !== savedNotes) && (
          <motion.div variants={staggerItem}>
            <button
              onClick={updateSession}
              disabled={updating}
              className="w-full rounded-xl border border-primary-500/40 bg-primary-500/10 py-3 text-sm font-semibold text-primary-400 transition-colors hover:bg-primary-500/20 disabled:opacity-50"
            >
              {updating ? "Salvando..." : "Salvar observações"}
            </button>
          </motion.div>
        )}

        {updateSuccess && (
          <motion.div variants={staggerItem} initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="rounded-lg bg-green-900/40 px-4 py-3 text-center text-sm text-green-400">
            Observações salvas ✓
          </motion.div>
        )}

        {showUpgrade && (
          <motion.div variants={staggerItem}>
            <UpgradeBanner />
          </motion.div>
        )}

        {saveError && (
          <motion.div variants={staggerItem} className="flex flex-col gap-2 rounded-lg bg-red-50 px-4 py-3">
            <p className="text-sm text-red-700">{saveError}</p>
            <button onClick={retrySave} disabled={saving} className="self-start text-xs font-semibold text-red-600 underline">
              Tentar novamente
            </button>
          </motion.div>
        )}

        {/* Share */}
        <motion.div variants={staggerItem}>
          <ShareButton
            workoutName={day.custom_name || day.name}
            durationMinutes={duration}
            volumeKg={totalVolume}
            exerciseCount={exercises.length}
            muscles={muscles}
            caloriesEstimated={savedCalories ?? undefined}
          />
        </motion.div>

        {/* Done CTA */}
        <motion.div variants={staggerItem}>
          <PressButton
            onClick={() => { if (!isSaved) onSaved?.(); setShowProfiling(true); }}
            className="w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white"
          >
            {isSaved ? "Ir para o dashboard →" : "Concluir sem salvar →"}
          </PressButton>
        </motion.div>
      </motion.div>

      <ProgressiveProfilingSheet
        open={showProfiling}
        trigger="post_workout"
        todayExercises={exercises.map((ex) => ({ exercise_id: ex.exercise_id, name: ex.name }))}
        onClose={() => { setShowProfiling(false); router.push("/dashboard"); }}
      />
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
    <div className="flex min-h-screen flex-col bg-[#0a0f1e] px-4 pt-6" style={{ paddingBottom: "var(--nav-pb)" }}>
      <div className="flex flex-1 flex-col">
        <p className="text-xs font-semibold uppercase tracking-wide text-primary-500">Aquecimento</p>
        <h1 className="mt-2 text-2xl font-bold text-white">Prepare o corpo</h1>
        <p className="mt-1 text-sm text-slate-400">Execute os movimentos abaixo antes de começar.</p>

        <div className="mt-6 space-y-3">
          {items.map((item, idx) => (
            <div key={idx} className="flex items-center gap-3 rounded-xl border border-slate-800 bg-slate-900 overflow-hidden">
              <img
                src={item.thumbnail}
                alt={item.label}
                className="h-20 w-24 flex-shrink-0 object-cover"
                onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
              />
              <div className="flex items-center gap-3 py-3 pr-4">
                <span className="flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full bg-primary-50 text-xs font-bold text-primary-600">{idx + 1}</span>
                <div>
                  <p className="font-medium text-white text-sm">{item.label}</p>
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
    <div className="flex min-h-screen flex-col bg-[#0a0f1e] px-4 pt-6" style={{ paddingBottom: "var(--nav-pb)" }}>
      <div className="flex flex-1 flex-col">
        <p className="text-xs font-semibold uppercase tracking-wide text-green-600">Finalização</p>
        <h1 className="mt-2 text-2xl font-bold text-white">Recuperação</h1>
        <p className="mt-1 text-sm text-slate-400">Alongamentos e respiração para encerrar o treino.</p>

        <div className="mt-6 space-y-3">
          {items.map((item, idx) => (
            <div key={idx} className="flex items-center gap-3 rounded-xl border border-slate-800 bg-slate-900 overflow-hidden">
              <img
                src={item.thumbnail}
                alt={item.label}
                className="h-20 w-24 flex-shrink-0 object-cover"
                onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
              />
              <div className="flex items-center gap-3 py-3 pr-4">
                <span className="flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full bg-green-50 text-xs font-bold text-green-600">{idx + 1}</span>
                <div>
                  <p className="font-medium text-white text-sm">{item.label}</p>
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

function createRuntime(exercise: WorkoutDayExercise, lastWeight?: string): ExerciseRuntime {
  const sets = exercise.sets || 1;
  return {
    planned_sets: sets,
    reps_by_set: Array.from({ length: sets }, () => exercise.reps || 0),
    weight_by_set: Array.from({ length: sets }, () => lastWeight ?? ""),
    warmup_by_set: Array.from({ length: sets }, () => false),
    rest_seconds: exercise.rest_seconds || 0,
    feeling: "",
    duration_minutes: exercise.duration_minutes ?? undefined,
    intensity: exercise.intensity ?? undefined,
    elapsed_seconds: 0,
  };
}

function runtimeFor(runtime: Record<number, ExerciseRuntime>, exercise: WorkoutDayExercise): ExerciseRuntime {
  return runtime[exercise.workout_day_exercise_id] ?? createRuntime(exercise);
}

function Metric({ label, value, highlight = false }: { label: string; value: number; highlight?: boolean }) {
  return (
    <div className="flex-1 rounded-xl bg-slate-900/60 p-4 text-center">
      <p className={`text-2xl font-bold ${highlight ? "text-primary-500" : "text-white"}`}>{value}</p>
      <p className="text-xs text-slate-400">{label}</p>
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
    <div className="rounded-xl bg-slate-900/60 p-3 text-center">
      <div className="flex items-center justify-center gap-2">
        <button onClick={onMinus} className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-900 text-lg font-bold text-slate-400">-</button>
        <p className="min-w-8 text-2xl font-bold text-white">{value}</p>
        <button onClick={onPlus} className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-900 text-lg font-bold text-slate-400">+</button>
      </div>
      <p className="mt-1 text-xs text-slate-400">{label}</p>
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

function getHistoricalMaxWeight(sessions: WorkoutSession[], exerciseId: number): number {
  let max = 0;
  for (const session of sessions) {
    for (const log of session.exercise_logs ?? []) {
      if (log.exercise_id !== exerciseId) continue;
      const weights: (number | null)[] = (log as { weight_by_set?: (number | null)[] }).weight_by_set ?? [];
      const warmups: boolean[] = (log as { is_warmup_by_set?: boolean[] }).is_warmup_by_set ?? [];
      if (weights.length > 0) {
        weights.forEach((w, i) => {
          if (!warmups[i] && w) max = Math.max(max, w);
        });
      } else if (log.weight_kg && !warmups[0]) {
        max = Math.max(max, log.weight_kg);
      }
    }
  }
  return max;
}

function firstWeight(weights: string[]) {
  const first = weights.find((value) => value !== "");
  return first ? Number(first) : null;
}

function formatWeights(weights: string[]) {
  const labels = weights.map((value, idx) => `S${idx + 1}: ${value ? `${value} kg` : "-"}`);
  return labels.join(" · ");
}

// ── ClosingOptionalScreen ────────────────────────────────────────────────────
const CARDIO_MODALITIES = [
  { key: "bike", label: "Bike", icon: "🚴" },
  { key: "esteira", label: "Esteira", icon: "🏃" },
  { key: "escada", label: "Escada", icon: "🪜" },
  { key: "remo", label: "Remo", icon: "🚣" },
  { key: "eliptico", label: "Elíptico", icon: "⚙️" },
];

const ABS_OPTIONS = [
  { key: "prancha", label: "Prancha", icon: "🧘", timed: true },
  { key: "crunch", label: "Abdominal crunch", icon: "💪", timed: false },
  { key: "elevacao_pernas", label: "Elevação de pernas", icon: "🦵", timed: false },
  { key: "infra", label: "Abdominal infra", icon: "📐", timed: false },
  { key: "obliquo", label: "Abdominal oblíquo", icon: "↗️", timed: false },
  { key: "bicicleta", label: "Abdominal bicicleta", icon: "🚲", timed: false },
];

function ClosingOptionalScreen({
  hasCardioAlready,
  hasCoreAlready,
  onFinish,
  onExtraCardio,
  onExtraAbs,
}: {
  hasCardioAlready: boolean;
  hasCoreAlready: boolean;
  onFinish: () => void;
  onExtraCardio: (data: Record<string, unknown>) => void;
  onExtraAbs: (data: Record<string, unknown>) => void;
}) {
  const [step, setStep] = useState<"choose" | "cardio" | "abs">("choose");
  const [cardioModality, setCardioModality] = useState("bike");
  const [cardioDuration, setCardioDuration] = useState(12);
  const [cardioIntensity, setCardioIntensity] = useState("moderado");
  const [selectedAbs, setSelectedAbs] = useState<string[]>([]);

  const showCardio = !hasCardioAlready;
  const showAbs = !hasCoreAlready;

  if (!showCardio && !showAbs) {
    onFinish();
    return null;
  }

  if (step === "cardio") {
    return (
      <div className="flex min-h-svh flex-col bg-[#0a0f1e] px-4 pt-8" style={{ paddingBottom: "var(--nav-pb)" }}>
        <p className="text-xs font-semibold uppercase tracking-wide text-primary-500 mb-1">Cardio extra</p>
        <h2 className="text-2xl font-bold text-white mb-6">Configure o cardio</h2>

        <div className="space-y-4">
          <div>
            <p className="text-sm text-slate-400 mb-2">Modalidade</p>
            <div className="flex flex-wrap gap-2">
              {CARDIO_MODALITIES.map(m => (
                <button key={m.key} onClick={() => setCardioModality(m.key)}
                  className={`flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-semibold border transition-all ${cardioModality === m.key ? "bg-primary-500 border-primary-500 text-white" : "border-slate-700 text-slate-300 bg-slate-900"}`}
                >
                  {m.icon} {m.label}
                </button>
              ))}
            </div>
          </div>

          <div>
            <p className="text-sm text-slate-400 mb-2">Duração: <strong className="text-white">{cardioDuration} min</strong></p>
            <input type="range" min={5} max={60} step={5} value={cardioDuration} onChange={e => setCardioDuration(Number(e.target.value))} className="w-full" />
          </div>

          <div>
            <p className="text-sm text-slate-400 mb-2">Intensidade</p>
            <div className="flex gap-2">
              {["leve", "moderado", "intenso"].map(i => (
                <button key={i} onClick={() => setCardioIntensity(i)}
                  className={`flex-1 rounded-xl py-2.5 text-sm font-semibold border ${cardioIntensity === i ? "bg-primary-500 border-primary-500 text-white" : "border-slate-700 text-slate-300 bg-slate-900"}`}
                >
                  {i.charAt(0).toUpperCase() + i.slice(1)}
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="mt-auto pt-6 space-y-3">
          <button onClick={() => onExtraCardio({ modality: cardioModality, duration_minutes: cardioDuration, intensity: cardioIntensity })}
            className="w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white"
          >
            Registrar cardio
          </button>
          <button onClick={onFinish} className="w-full py-3 text-sm text-slate-500">Pular e finalizar</button>
        </div>
      </div>
    );
  }

  if (step === "abs") {
    return (
      <div className="flex min-h-svh flex-col bg-[#0a0f1e] px-4 pt-8" style={{ paddingBottom: "var(--nav-pb)" }}>
        <p className="text-xs font-semibold uppercase tracking-wide text-primary-500 mb-1">Core extra</p>
        <h2 className="text-2xl font-bold text-white mb-6">Escolha os exercícios</h2>

        <div className="space-y-2">
          {ABS_OPTIONS.map(opt => (
            <button key={opt.key}
              onClick={() => setSelectedAbs(prev => prev.includes(opt.key) ? prev.filter(k => k !== opt.key) : [...prev, opt.key])}
              className={`flex w-full items-center gap-3 rounded-xl border p-3 text-left transition-all ${selectedAbs.includes(opt.key) ? "border-primary-500 bg-primary-500/10" : "border-slate-800 bg-slate-900"}`}
            >
              <span className="text-xl">{opt.icon}</span>
              <span className={`text-sm font-semibold ${selectedAbs.includes(opt.key) ? "text-primary-400" : "text-white"}`}>{opt.label}</span>
              {opt.timed && <span className="ml-auto text-xs text-slate-500">⏱ timed</span>}
            </button>
          ))}
        </div>

        <div className="mt-auto pt-6 space-y-3">
          <button
            onClick={() => selectedAbs.length > 0
              ? onExtraAbs({ exercises: selectedAbs.map(k => ABS_OPTIONS.find(o => o.key === k)!.label) })
              : onFinish()
            }
            className="w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white"
          >
            {selectedAbs.length > 0 ? `Registrar ${selectedAbs.length} exercício${selectedAbs.length > 1 ? "s" : ""}` : "Pular"}
          </button>
          <button onClick={onFinish} className="w-full py-3 text-sm text-slate-500">Pular e finalizar</button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-svh flex-col items-center justify-center bg-[#0a0f1e] px-6" style={{ paddingBottom: "var(--nav-pb)" }}>
      <div className="text-center mb-8">
        <div className="text-4xl mb-3">💪</div>
        <h2 className="text-2xl font-bold text-white">Treino principal concluído!</h2>
        <p className="mt-2 text-slate-400 text-sm">Quer fechar com algo extra?</p>
      </div>

      <div className="w-full max-w-sm space-y-3">
        {showCardio && (
          <button onClick={() => setStep("cardio")}
            className="flex w-full items-center gap-4 rounded-2xl border border-slate-700 bg-slate-900 p-4 text-left hover:border-primary-500/50 transition-all"
          >
            <span className="text-2xl">🚴</span>
            <div>
              <p className="font-semibold text-white">Fazer cardio</p>
              <p className="text-xs text-slate-500">Bike, esteira, remo e mais</p>
            </div>
          </button>
        )}
        {showAbs && (
          <button onClick={() => setStep("abs")}
            className="flex w-full items-center gap-4 rounded-2xl border border-slate-700 bg-slate-900 p-4 text-left hover:border-primary-500/50 transition-all"
          >
            <span className="text-2xl">🔥</span>
            <div>
              <p className="font-semibold text-white">Fazer abdominais</p>
              <p className="text-xs text-slate-500">Prancha, crunch, elevação e mais</p>
            </div>
          </button>
        )}
        <button onClick={onFinish}
          className="w-full rounded-2xl bg-primary-500 py-4 text-base font-semibold text-white"
        >
          Finalizar treino agora
        </button>
      </div>
    </div>
  );
}

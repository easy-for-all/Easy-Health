"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { WorkoutPlan, WorkoutDayExercise } from "@/shared/types/workout";
import type { HealthProfile } from "@/shared/types/health-profile";
import { SwapModal } from "../workout/today/swap-modal";
import { getGymSafeImageUrl } from "@/shared/utils/exercise-image";
import { AITrainerBubble } from "@/shared/components/ai-trainer";
import { AgentOrb } from "@/shared/components/agent-orb";
import { PlanCreationFlow } from "@/features/plan-creation/plan-creation-flow";
import "@/shared/components/ui/ui.css";

const MUSCLE_COLORS: Record<string, string> = {
  chest: "bg-red-100 text-red-700",
  back: "bg-blue-100 text-blue-700",
  shoulders: "bg-purple-100 text-purple-700",
  biceps: "bg-yellow-100 text-yellow-700",
  triceps: "bg-orange-100 text-orange-700",
  legs: "bg-green-100 text-green-700",
  core: "bg-teal-100 text-teal-700",
};

type PlanSummary = {
  id: number;
  active: boolean;
  created_at: string;
  days_count: number;
  days: { id: number; name: string; exercise_count: number }[];
};

type Phase = "loading" | "view" | "wizard";

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

export default function PlanPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const forceWizard = searchParams.get("wizard") === "1";
  const [phase, setPhase] = useState<Phase>("loading");
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [allPlans, setAllPlans] = useState<PlanSummary[]>([]);
  const [showHistory, setShowHistory] = useState(false);
  const [profile, setProfile] = useState<HealthProfile | null>(null);
  const [selectedDayId, setSelectedDayId] = useState<number | null>(null);
  const [planSummary, setPlanSummary] = useState<string | null>(null);
  const [planRationale, setPlanRationale] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<HealthProfile>("/api/v1/health_profile").catch(() => null),
      api.get<PlanSummary[]>("/api/v1/workout_plans").catch(() => []),
    ]).then(([p, hp, plans]) => {
      setPlan(p);
      setPlanRationale(p?.personalization_reason ?? p?.strategy?.user_facing_explanation ?? p?.ai_rationale ?? null);
      setProfile(hp);
      setAllPlans(plans ?? []);
      if (p && !forceWizard) {
        router.replace("/workouts");
        return;
      }
      setPhase("wizard");
    });
  }, []);

  async function handleToggleFavorite(dayId: number) {
    try {
      const resp = await api.patch<{ favorited: boolean }>(`/api/v1/workout_days/${dayId}/toggle_favorite`, {});
      if (plan) {
        setPlan({
          ...plan,
          days: plan.days.map((d) => d.id === dayId ? { ...d, favorited: resp.favorited } : d),
        });
      }
    } catch {
      // ignore
    }
  }

  async function handleDuplicateDay(dayId: number) {
    try {
      const { day: newDay } = await api.post<{ day: import("@/shared/types/workout").WorkoutDay }>(
        `/api/v1/workout_days/${dayId}/duplicate`,
        {}
      );
      if (plan) {
        setPlan({
          ...plan,
          days: [...plan.days, { ...newDay, exercise_count: newDay.exercises?.length ?? 0 }],
        });
      }
      setSelectedDayId(newDay.id);
    } catch {
      // best-effort; the day list refreshes on next load if this fails
    }
  }

  if (phase === "loading") return <LoadingScreen />;

  if (phase === "wizard") {
    return (
      <PlanCreationFlow
        entryMode={profile ? "replan" : "onboarding"}
        initialProfile={profile}
        onCancel={plan ? () => setPhase("view") : undefined}
        onDone={(newPlan) => {
          setPlan(newPlan);
          setPlanSummary((newPlan as WorkoutPlan & { summary?: string }).summary ?? null);
          setPlanRationale(newPlan.personalization_reason ?? newPlan.strategy?.user_facing_explanation ?? newPlan.ai_rationale ?? null);
          setPhase("view");
        }}
      />
    );
  }

  return (
    <div style={{ minHeight: "100svh", background: "var(--bg)", color: "var(--text)", padding: "52px 20px 100px" }}>
      <header style={{ marginBottom: 20, display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: 24, fontWeight: 700, letterSpacing: "-0.02em", margin: 0 }}>
          Seu Plano
        </h1>
        <button
          onClick={() => router.push("/dashboard")}
          style={{ background: "var(--primary-soft)", color: "var(--primary)", border: "none", borderRadius: "var(--r-pill)", padding: "8px 14px", fontSize: 13, fontWeight: 700, cursor: "pointer" }}
        >
          ✨ Dicas IA
        </button>
      </header>

      {plan && (
        <>
          {(planSummary || planRationale) && (
            <div style={{ marginBottom: 16, display: "flex", alignItems: "flex-start", gap: 12, background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--r-lg)", padding: "16px 18px" }}>
              <AgentOrb size="card" glyph />
              <div style={{ flex: 1 }}>
                <p style={{ fontSize: 14.5, fontWeight: 700, margin: "0 0 6px" }}>Coach EasyHealth</p>
                <AITrainerBubble
                  message={planRationale ?? planSummary ?? "Seu plano está pronto!"}
                  mood="speaking"
                  show
                  side="left"
                />
              </div>
            </div>
          )}
          {plan.created_at && <PlanAgeAlert createdAt={plan.created_at} onReplanejar={() => setPhase("wizard")} />}
          <PlanView plan={plan} onDayClick={setSelectedDayId} onDuplicate={handleDuplicateDay} onToggleFavorite={handleToggleFavorite} />
          <button
            onClick={() => setPhase("wizard")}
            style={{ marginTop: 16, width: "100%", background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--r-lg)", padding: "14px", color: "var(--text-muted)", fontWeight: 600, fontSize: 14, cursor: "pointer" }}
          >
            ↺ Replanejar
          </button>
          {allPlans.length > 1 && (
            <div className="mt-6">
              <button
                onClick={() => setShowHistory((v) => !v)}
                className="flex w-full items-center justify-between rounded-xl border border-gray-100 bg-white px-4 py-3 dark:border-gray-800 dark:bg-gray-900"
              >
                <span className="text-sm font-semibold text-gray-700 dark:text-gray-300">Treinos anteriores</span>
                <span className="text-xs text-gray-400 dark:text-gray-500">{showHistory ? "▲ Ocultar" : "▼ Ver"}</span>
              </button>
              {showHistory && (
                <div className="mt-2 space-y-2">
                  {allPlans.filter((p) => !p.active).map((p) => (
                    <PlanHistoryCard key={p.id} plan={p} />
                  ))}
                </div>
              )}
            </div>
          )}
        </>
      )}

      {selectedDayId != null && (
        <PlanDayDetailDrawer
          dayId={selectedDayId}
          onClose={() => setSelectedDayId(null)}
          onChanged={(updatedDay) => {
            if (!plan) return;
            setPlan({
              ...plan,
              days: plan.days.map((d) => (d.id === updatedDay.id ? { ...d, exercise_count: updatedDay.exercises?.length ?? d.exercise_count } : d)),
            });
          }}
        />
      )}
    </div>
  );
}

// ── Existing components ───────────────────────────────────────────────────────

function PlanView({
  plan,
  onDayClick,
  onDuplicate,
  onToggleFavorite,
}: {
  plan: WorkoutPlan;
  onDayClick: (dayId: number) => void;
  onDuplicate?: (dayId: number) => void;
  onToggleFavorite?: (dayId: number) => Promise<void>;
}) {
  return (
    <div className="space-y-3">
      {plan.days?.map((day, idx) => (
        <div
          key={day.id}
          className="rounded-xl border border-gray-100 bg-white transition hover:border-primary-200 hover:bg-primary-50 dark:border-gray-800 dark:bg-gray-900 dark:hover:border-primary-800 dark:hover:bg-primary-950/30"
        >
          <button
            onClick={() => day.id !== null && onDayClick(day.id)}
            className="w-full p-4 text-left"
          >
            <div className="flex items-center justify-between">
              <div>
                <p className="text-xs font-semibold text-gray-400 dark:text-gray-500">Treino {LETTERS[idx] ?? idx + 1}</p>
                <p className="font-semibold text-gray-900 dark:text-gray-50">{day.name}</p>
                <p className="mt-0.5 text-xs text-gray-400">{day.exercise_count} exercícios</p>
                {day.muscle_groups?.length ? (
                  <div className="mt-1 flex flex-wrap gap-1">
                    {day.muscle_groups.slice(0, 3).map((m) => (
                      <span key={m} className={`rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[m] ?? "bg-gray-100 text-gray-600"}`}>{m}</span>
                    ))}
                  </div>
                ) : null}
              </div>
              <span className="text-lg text-gray-300 dark:text-gray-600">›</span>
            </div>
          </button>
          {(onToggleFavorite || (onDuplicate && day.favorited)) && (
            <div className="border-t border-gray-50 px-4 pb-3 pt-2 flex items-center gap-4 dark:border-gray-800">
              {onToggleFavorite && (
                <button
                  onClick={() => day.id !== null && onToggleFavorite(day.id)}
                  className="text-base leading-none transition-transform active:scale-110"
                  aria-label={day.favorited ? "Remover dos favoritos" : "Adicionar aos favoritos"}
                >
                  {day.favorited ? "❤️" : "🤍"}
                </button>
              )}
              {onDuplicate && day.favorited && (
                <button
                  onClick={() => day.id !== null && onDuplicate(day.id)}
                  className="text-xs font-medium text-gray-400 hover:text-primary-600 dark:hover:text-primary-400"
                >
                  + Duplicar treino
                </button>
              )}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

function weeksAgo(dateStr: string): number {
  return Math.floor((Date.now() - new Date(dateStr).getTime()) / (7 * 24 * 60 * 60 * 1000));
}

function PlanAgeAlert({ createdAt, onReplanejar }: { createdAt: string; onReplanejar: () => void }) {
  const weeks = weeksAgo(createdAt);
  if (weeks < 4) return null;

  let bg = "bg-yellow-50 border-yellow-200 text-yellow-800 dark:bg-yellow-950/30 dark:border-yellow-800/40 dark:text-yellow-300";
  let message = "Seu corpo pode já ter se adaptado a este treino. Considere evoluir a carga.";
  let showButton = false;

  if (weeks >= 8) {
    bg = "bg-red-50 border-red-200 text-red-800 dark:bg-red-950/30 dark:border-red-800/40 dark:text-red-300";
    message = "Plano com mais de 8 semanas. Sugerimos um replanejamento completo.";
    showButton = true;
  } else if (weeks >= 6) {
    bg = "bg-orange-50 border-orange-200 text-orange-800 dark:bg-orange-950/30 dark:border-orange-800/40 dark:text-orange-300";
    message = "Recomendamos revisar ou evoluir este plano em breve.";
    showButton = true;
  }

  return (
    <div className={`mb-3 flex items-start gap-3 rounded-xl border px-4 py-3 ${bg}`}>
      <span className="mt-0.5 text-base">⏱️</span>
      <div className="flex-1 min-w-0">
        <p className="text-xs font-semibold">Plano criado há {weeks} semana{weeks === 1 ? "" : "s"}</p>
        <p className="mt-0.5 text-xs opacity-80">{message}</p>
      </div>
      {showButton && (
        <button
          onClick={onReplanejar}
          className="shrink-0 rounded-lg bg-white/60 px-2.5 py-1 text-xs font-semibold dark:bg-white/10"
        >
          Replanejar
        </button>
      )}
    </div>
  );
}

function PlanHistoryCard({ plan }: { plan: PlanSummary }) {
  const [expanded, setExpanded] = useState(false);
  return (
    <div className="rounded-xl border border-gray-100 bg-white p-4 dark:border-gray-800 dark:bg-gray-900">
      <button className="flex w-full items-center justify-between" onClick={() => setExpanded((v) => !v)}>
        <div className="text-left">
          <p className="text-sm font-semibold text-gray-700 dark:text-gray-300">
            Criado há {weeksAgo(plan.created_at)} semana{weeksAgo(plan.created_at) === 1 ? "" : "s"}
          </p>
          <p className="text-xs text-gray-400">{plan.days_count} dias · {plan.days.reduce((s, d) => s + d.exercise_count, 0)} exercícios</p>
        </div>
        <span className="text-xs text-gray-400">{expanded ? "▲" : "▼"}</span>
      </button>
      {expanded && (
        <div className="mt-3 space-y-2 border-t border-gray-50 pt-3">
          {plan.days.map((d, i) => (
            <div key={d.id} className="flex items-center gap-2">
              <span className="flex h-6 w-6 items-center justify-center rounded-full bg-gray-100 text-xs font-bold text-gray-500">{LETTERS[i] ?? i + 1}</span>
              <p className="text-sm text-gray-700">{d.name}</p>
              <span className="ml-auto text-xs text-gray-400">{d.exercise_count} ex.</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Plan Day Detail Drawer ────────────────────────────────────────────────────

const CARDIO_EXERCISE_TYPES = ["cardio", "corrida", "caminhada", "hiit", "natacao"] as const;
function isCardioEx(ex: { exercise_type: string }) {
  return CARDIO_EXERCISE_TYPES.includes(ex.exercise_type as (typeof CARDIO_EXERCISE_TYPES)[number]);
}

const INTENSITIES = [
  { value: "leve", label: "Leve", color: "text-green-700 bg-green-50" },
  { value: "moderado", label: "Moderado", color: "text-yellow-700 bg-yellow-50" },
  { value: "intenso", label: "Intenso", color: "text-red-700 bg-red-50" },
] as const;

type ExerciseEdits = Record<number, { sets?: number; reps?: number; duration_minutes?: number; intensity?: string }>;

type AddExerciseOption = {
  id: number;
  name: string;
  muscle_group: string | null;
  exercise_type: string;
  image_url: string;
};

type CardioAddConfig = { exerciseId: number; duration: number; intensity: string };

function PlanDayDetailDrawer({
  dayId,
  onClose,
  onChanged,
}: {
  dayId: number;
  onClose: () => void;
  onChanged: (day: import("@/shared/types/workout").WorkoutDay) => void;
}) {
  const [day, setDay] = useState<import("@/shared/types/workout").WorkoutDay | null>(null);
  const [exercises, setExercises] = useState<WorkoutDayExercise[]>([]);
  const [edits, setEdits] = useState<ExerciseEdits>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [drawerError, setDrawerError] = useState("");
  const [swapTarget, setSwapTarget] = useState<WorkoutDayExercise | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [addSearch, setAddSearch] = useState("");
  const [addResults, setAddResults] = useState<AddExerciseOption[]>([]);
  const [addLoading, setAddLoading] = useState(false);
  const [addTypeFilter, setAddTypeFilter] = useState<"all" | "cardio">("all");
  const [cardioConfig, setCardioConfig] = useState<CardioAddConfig | null>(null);
  const addTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    api.get<{ day: import("@/shared/types/workout").WorkoutDay }>(`/api/v1/workout_days/${dayId}`)
      .then(({ day: d }) => {
        setDay(d);
        setExercises(d.exercises ?? []);
      })
      .catch(() => setDrawerError("Erro ao carregar exercícios."))
      .finally(() => setLoading(false));
  }, [dayId]);

  const fetchAddOptions = useCallback(async (name: string, typeFilter: "all" | "cardio" = "all") => {
    setAddLoading(true);
    try {
      const params = new URLSearchParams({ name, exclude_ids: exercises.map((e) => e.exercise_id).join(",") });
      if (typeFilter === "cardio") params.set("exercise_types", CARDIO_EXERCISE_TYPES.join(","));
      const data = await api.get<AddExerciseOption[]>(`/api/v1/exercises?${params}`);
      const filtered = typeFilter === "cardio"
        ? data.filter((e) => isCardioEx(e))
        : data;
      setAddResults(filtered);
    } catch {
      setAddResults([]);
    } finally {
      setAddLoading(false);
    }
  }, [exercises]);

  function handleAddSearchChange(value: string) {
    setAddSearch(value);
    if (addTimerRef.current) clearTimeout(addTimerRef.current);
    addTimerRef.current = setTimeout(() => fetchAddOptions(value, addTypeFilter), 300);
  }

  function openAdd() {
    setAddSearch("");
    setAddResults([]);
    setAddTypeFilter("all");
    setCardioConfig(null);
    setShowAdd(true);
    fetchAddOptions("");
  }

  function handleAddTypeFilter(type: "all" | "cardio") {
    setAddTypeFilter(type);
    fetchAddOptions(addSearch, type);
  }

  function setField(id: number, field: "sets" | "reps", raw: string) {
    const value = Math.max(1, parseInt(raw, 10) || 1);
    setEdits((prev) => ({ ...prev, [id]: { ...prev[id], [field]: value } }));
  }

  function currentValue(ex: WorkoutDayExercise, field: "sets" | "reps"): number {
    return edits[ex.workout_day_exercise_id]?.[field] ?? ex[field];
  }

  async function handleDelete(id: number) {
    setDrawerError("");
    try {
      await api.delete(`/api/v1/workout_day_exercises/${id}`);
      const updated = exercises.filter((e) => e.workout_day_exercise_id !== id);
      setExercises(updated);
      if (day) onChanged({ ...day, exercises: updated });
    } catch (e: unknown) {
      setDrawerError(e instanceof Error ? e.message : "Erro ao excluir exercício.");
    }
  }

  async function handleSwap(wdeId: number, replacementId: number) {
    const updated = await api.post<WorkoutDayExercise>(
      `/api/v1/workout_day_exercises/${wdeId}/swap`,
      { replacement_exercise_id: replacementId }
    );
    const newList = exercises.map((e) => e.workout_day_exercise_id === wdeId ? updated : e);
    setExercises(newList);
    setSwapTarget(null);
    if (day) onChanged({ ...day, exercises: newList });
  }

  async function handleAdd(exerciseId: number, cardioParams?: { duration_minutes: number; intensity: string }) {
    if (!day) return;
    setDrawerError("");
    try {
      const body: Record<string, unknown> = { exercise_id: exerciseId };
      if (cardioParams) {
        body.duration_minutes = cardioParams.duration_minutes;
        body.intensity = cardioParams.intensity;
      }
      const created = await api.post<WorkoutDayExercise>(
        `/api/v1/workout_days/${day.id}/exercises`,
        body
      );
      const newList = [...exercises, created];
      setExercises(newList);
      setShowAdd(false);
      setCardioConfig(null);
      if (day) onChanged({ ...day, exercises: newList });
    } catch (e: unknown) {
      setDrawerError(e instanceof Error ? e.message : "Erro ao adicionar exercício.");
    }
  }

  async function handleMove(id: number, direction: "up" | "down") {
    if (!day) return;
    const idx = exercises.findIndex((e) => e.workout_day_exercise_id === id);
    if (idx === -1) return;
    if (direction === "up" && idx === 0) return;
    if (direction === "down" && idx === exercises.length - 1) return;
    const newList = [...exercises];
    const swapIdx = direction === "up" ? idx - 1 : idx + 1;
    [newList[idx], newList[swapIdx]] = [newList[swapIdx], newList[idx]];
    setExercises(newList);
    try {
      await api.patch(`/api/v1/workout_days/${day.id}/exercises/reorder`, {
        ordered_ids: newList.map((e) => e.workout_day_exercise_id),
      });
    } catch {
      setExercises(exercises);
    }
  }

  async function handleSave() {
    setSaving(true);
    setDrawerError("");
    try {
      await Promise.all(
        Object.entries(edits).map(([id, vals]) => {
          const ex = exercises.find((e) => e.workout_day_exercise_id === Number(id));
          if (!ex) return Promise.resolve();
          if (isCardioEx(ex)) {
            return api.patch(`/api/v1/workout_day_exercises/${id}`, {
              duration_minutes: vals.duration_minutes ?? ex.duration_minutes,
              intensity: vals.intensity ?? ex.intensity,
            });
          }
          return api.patch(`/api/v1/workout_day_exercises/${id}`, {
            sets: vals.sets ?? ex.sets,
            reps: vals.reps ?? ex.reps,
          });
        })
      );
      setEdits({});
      if (day) onChanged(day);
      onClose();
    } catch {
      setDrawerError("Erro ao salvar. Tente novamente.");
    } finally {
      setSaving(false);
    }
  }

  const hasDirty = Object.keys(edits).length > 0;

  return (
    <>
      <div className="fixed inset-0 z-50 flex items-end bg-black/50" onClick={onClose}>
        <div
          className="max-h-[90vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-8 pt-4 dark:bg-gray-900"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-gray-200 dark:bg-gray-700" />
          <div className="flex items-center justify-between mt-2 mb-4">
            <h3 className="text-base font-bold text-gray-900 dark:text-gray-50">{day?.name ?? "Treino"}</h3>
            <button onClick={onClose} className="text-sm text-gray-400 hover:text-gray-600 dark:hover:text-gray-300">Fechar</button>
          </div>

          {loading && <p className="py-8 text-center text-sm text-gray-400">Carregando...</p>}

          {!loading && drawerError && (
            <p className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{drawerError}</p>
          )}

          {!loading && exercises.length === 0 && !drawerError && (
            <p className="py-8 text-center text-sm text-gray-400">Nenhum exercício neste treino.</p>
          )}

          <div className="space-y-3">
            {exercises.map((ex) => (
              <div key={ex.workout_day_exercise_id} className="rounded-xl border border-gray-100 bg-white p-3">
                <div className="flex gap-3 mb-3">
                  {/* Exercise image */}
                  <img
                    src={getGymSafeImageUrl(ex) ?? `/exercise-images/${ex.exercise_type || "treino"}.svg`}
                    alt={ex.name}
                    className="h-16 w-20 rounded-lg object-cover flex-shrink-0"
                    onError={(e) => { e.currentTarget.onerror = null; e.currentTarget.src = `/exercise-images/${ex.exercise_type || "treino"}.svg`; }}
                  />
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-gray-900 text-sm leading-tight">{ex.name}</p>
                    {isCardioEx(ex) ? (
                      <p className="text-xs text-gray-400 mt-0.5">
                        {edits[ex.workout_day_exercise_id]?.duration_minutes ?? ex.duration_minutes ?? 20} min
                        {" · "}
                        <span className={`capitalize ${INTENSITIES.find(i => i.value === (edits[ex.workout_day_exercise_id]?.intensity ?? ex.intensity))?.color ?? "text-gray-400"}`}>
                          {INTENSITIES.find(i => i.value === (edits[ex.workout_day_exercise_id]?.intensity ?? ex.intensity))?.label ?? "Moderado"}
                        </span>
                      </p>
                    ) : (
                      <p className="text-xs text-gray-400 mt-0.5">
                        {currentValue(ex, "sets")} séries · {currentValue(ex, "reps")} reps
                      </p>
                    )}
                    <div className="flex gap-3 mt-2">
                      <button
                        onClick={() => setSwapTarget(ex)}
                        className="text-xs font-medium text-primary-500 hover:text-primary-700"
                      >
                        Trocar
                      </button>
                      <button
                        onClick={() => handleDelete(ex.workout_day_exercise_id)}
                        className="text-xs font-medium text-red-400 hover:text-red-600"
                      >
                        Excluir
                      </button>
                    </div>
                  </div>
                  <div className="flex flex-col gap-1 justify-center">
                    <button
                      onClick={() => handleMove(ex.workout_day_exercise_id, "up")}
                      disabled={exercises.indexOf(ex) === 0}
                      className="flex h-7 w-7 items-center justify-center rounded-lg border border-gray-200 text-xs text-gray-400 disabled:opacity-25 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-800"
                    >↑</button>
                    <button
                      onClick={() => handleMove(ex.workout_day_exercise_id, "down")}
                      disabled={exercises.indexOf(ex) === exercises.length - 1}
                      className="flex h-7 w-7 items-center justify-center rounded-lg border border-gray-200 text-xs text-gray-400 disabled:opacity-25 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-800"
                    >↓</button>
                  </div>
                </div>

                {/* Editable fields: sets/reps for strength, duration/intensity for cardio */}
                {isCardioEx(ex) ? (
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs text-gray-400 mb-1">Duração (min)</label>
                      <input
                        type="number"
                        min={1}
                        max={120}
                        value={edits[ex.workout_day_exercise_id]?.duration_minutes ?? ex.duration_minutes ?? 20}
                        onChange={(e) => setEdits((prev) => ({
                          ...prev,
                          [ex.workout_day_exercise_id]: {
                            ...prev[ex.workout_day_exercise_id],
                            duration_minutes: Math.max(1, parseInt(e.target.value, 10) || 1),
                          },
                        }))}
                        className="w-full rounded-lg border border-gray-200 px-3 py-2 text-center text-sm font-semibold focus:border-primary-500 focus:outline-none"
                      />
                    </div>
                    <div>
                      <label className="block text-xs text-gray-400 mb-1">Intensidade</label>
                      <select
                        value={edits[ex.workout_day_exercise_id]?.intensity ?? ex.intensity ?? "moderado"}
                        onChange={(e) => setEdits((prev) => ({
                          ...prev,
                          [ex.workout_day_exercise_id]: {
                            ...prev[ex.workout_day_exercise_id],
                            intensity: e.target.value,
                          },
                        }))}
                        className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm font-semibold focus:border-primary-500 focus:outline-none"
                      >
                        {INTENSITIES.map((i) => <option key={i.value} value={i.value}>{i.label}</option>)}
                      </select>
                    </div>
                  </div>
                ) : (
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs text-gray-400 mb-1">Séries</label>
                      <input
                        type="number"
                        min={1}
                        max={10}
                        value={currentValue(ex, "sets")}
                        onChange={(e) => setField(ex.workout_day_exercise_id, "sets", e.target.value)}
                        className="w-full rounded-lg border border-gray-200 px-3 py-2 text-center text-sm font-semibold focus:border-primary-500 focus:outline-none"
                      />
                    </div>
                    <div>
                      <label className="block text-xs text-gray-400 mb-1">Reps</label>
                      <input
                        type="number"
                        min={1}
                        max={100}
                        value={currentValue(ex, "reps")}
                        onChange={(e) => setField(ex.workout_day_exercise_id, "reps", e.target.value)}
                        className="w-full rounded-lg border border-gray-200 px-3 py-2 text-center text-sm font-semibold focus:border-primary-500 focus:outline-none"
                      />
                    </div>
                  </div>
                )}
              </div>
            ))}
          </div>

          {!loading && (
            <button
              onClick={openAdd}
              className="mt-4 w-full rounded-xl border border-dashed border-primary-300 py-3 text-sm font-semibold text-primary-600 hover:bg-primary-50"
            >
              + Adicionar exercício
            </button>
          )}

          {!loading && exercises.length > 0 && (
            <button
              onClick={handleSave}
              disabled={saving || !hasDirty}
              className="mt-3 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white disabled:opacity-50 hover:bg-primary-600"
            >
              {saving ? "Salvando..." : "Salvar alterações"}
            </button>
          )}
        </div>
      </div>

      {/* Swap modal */}
      {swapTarget && (
        <SwapModal
          exercise={swapTarget}
          onSwap={handleSwap}
          onClose={() => setSwapTarget(null)}
        />
      )}

      {/* Add exercise sheet */}
      {showAdd && (
        <div
          className="fixed inset-0 z-[60] flex items-end bg-black/40"
          onClick={() => { setShowAdd(false); setAddSearch(""); setCardioConfig(null); }}
        >
          <div
            className="max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-24 pt-4 dark:bg-gray-900"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-gray-200" />
            <h3 className="mb-3 mt-2 text-base font-bold text-gray-900">Adicionar exercício</h3>

            {/* Type filter chips */}
            <div className="mb-3 flex gap-2">
              <button
                onClick={() => handleAddTypeFilter("all")}
                className={`rounded-full px-3 py-1 text-xs font-semibold transition ${addTypeFilter === "all" ? "bg-primary-500 text-white" : "bg-gray-100 text-gray-600"}`}
              >
                Todos
              </button>
              <button
                onClick={() => handleAddTypeFilter("cardio")}
                className={`rounded-full px-3 py-1 text-xs font-semibold transition ${addTypeFilter === "cardio" ? "bg-orange-500 text-white" : "bg-gray-100 text-gray-600"}`}
              >
                🏃 Cardio
              </button>
            </div>

            <input
              type="text"
              placeholder="Buscar por nome..."
              value={addSearch}
              onChange={(e) => handleAddSearchChange(e.target.value)}
              className="mb-3 w-full rounded-xl border border-gray-200 px-4 py-2.5 text-sm focus:border-primary-500 focus:outline-none"
            />

            {/* Cardio config step */}
            {cardioConfig && (
              <div className="mb-4 rounded-xl border border-orange-200 bg-orange-50 p-4">
                <p className="mb-3 text-sm font-semibold text-orange-800">Configurar cardio</p>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs text-gray-600 mb-1">Duração (min)</label>
                    <input
                      type="number"
                      min={1}
                      max={120}
                      value={cardioConfig.duration}
                      onChange={(e) => setCardioConfig((p) => p ? { ...p, duration: Math.max(1, parseInt(e.target.value, 10) || 1) } : p)}
                      className="w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-center text-sm font-semibold focus:border-orange-400 focus:outline-none dark:border-gray-700 dark:bg-gray-800 dark:text-gray-50"
                    />
                  </div>
                  <div>
                    <label className="block text-xs text-gray-600 mb-1">Intensidade</label>
                    <select
                      value={cardioConfig.intensity}
                      onChange={(e) => setCardioConfig((p) => p ? { ...p, intensity: e.target.value } : p)}
                      className="w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm font-semibold focus:border-orange-400 focus:outline-none dark:border-gray-700 dark:bg-gray-800 dark:text-gray-50"
                    >
                      {INTENSITIES.map((i) => <option key={i.value} value={i.value}>{i.label}</option>)}
                    </select>
                  </div>
                </div>
                <div className="mt-3 flex gap-2">
                  <button
                    onClick={() => handleAdd(cardioConfig.exerciseId, { duration_minutes: cardioConfig.duration, intensity: cardioConfig.intensity })}
                    className="flex-1 rounded-lg bg-orange-500 py-2 text-sm font-semibold text-white hover:bg-orange-600"
                  >
                    Adicionar
                  </button>
                  <button
                    onClick={() => setCardioConfig(null)}
                    className="rounded-lg border border-gray-200 px-4 py-2 text-sm text-gray-500"
                  >
                    Cancelar
                  </button>
                </div>
              </div>
            )}

            {addLoading ? (
              <p className="rounded-lg bg-gray-50 p-3 text-center text-sm text-gray-400">Buscando...</p>
            ) : addResults.length === 0 ? (
              <p className="rounded-lg bg-gray-50 p-3 text-sm text-gray-500">Nenhum exercício encontrado.</p>
            ) : (
              addResults.map((opt) => (
                <button
                  key={opt.id}
                  onClick={() => {
                    if (isCardioEx(opt)) {
                      setCardioConfig({ exerciseId: opt.id, duration: 20, intensity: "moderado" });
                    } else {
                      handleAdd(opt.id);
                    }
                  }}
                  className="mb-2 flex w-full gap-3 rounded-lg border border-gray-100 p-3 text-left hover:bg-gray-50"
                >
                  <img
                    src={getGymSafeImageUrl(opt) ?? `/exercise-images/${opt.exercise_type || "treino"}.svg`}
                    alt={opt.name}
                    className="h-12 w-16 rounded-md object-cover flex-shrink-0"
                    onError={(e) => { e.currentTarget.onerror = null; e.currentTarget.src = `/exercise-images/${opt.exercise_type || "treino"}.svg`; }}
                  />
                  <div className="flex-1">
                    <p className="font-medium text-gray-900">{opt.name}</p>
                    <p className="text-xs text-gray-400">{opt.muscle_group ?? opt.exercise_type}</p>
                  </div>
                  {isCardioEx(opt) && (
                    <span className="self-center rounded-full bg-orange-100 px-2 py-0.5 text-xs font-semibold text-orange-700">Cardio</span>
                  )}
                </button>
              ))
            )}
          </div>
        </div>
      )}
    </>
  );
}

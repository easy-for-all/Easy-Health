"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { UpgradeGate } from "@/shared/components/upgrade-gate";
import { useWorkoutSession, formatElapsed } from "@/features/workout/workout-session-context";
import type { WorkoutPlan, WorkoutDay, WorkoutSession } from "@/shared/types/workout";

const MUSCLE_COLORS: Record<string, string> = {
  chest: "bg-red-500/20 text-red-300",
  back: "bg-blue-500/20 text-blue-300",
  shoulders: "bg-purple-500/20 text-purple-300",
  biceps: "bg-yellow-500/20 text-yellow-300",
  triceps: "bg-orange-500/20 text-orange-300",
  legs: "bg-green-500/20 text-green-300",
  core: "bg-teal-500/20 text-teal-300",
};

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

function recommendedDayId(plan: WorkoutPlan, sessions: WorkoutSession[]): number | null {
  if (!sessions.length) return plan.days[0]?.id ?? null;
  const lastSession = [...sessions].sort(
    (a, b) => new Date(b.completed_at).getTime() - new Date(a.completed_at).getTime()
  )[0];
  const lastIdx = plan.days.findIndex((d) => d.id === lastSession.workout_day_id);
  if (lastIdx === -1) return plan.days[0]?.id ?? null;
  return plan.days[(lastIdx + 1) % plan.days.length]?.id ?? null;
}

function lastSessionForDay(sessions: WorkoutSession[], dayId: number): WorkoutSession | null {
  return (
    sessions
      .filter((s) => s.workout_day_id === dayId)
      .sort((a, b) => new Date(b.completed_at).getTime() - new Date(a.completed_at).getTime())[0] ?? null
  );
}

function relativeDate(dateStr: string): string {
  const daysAgo = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (daysAgo === 0) return "feito hoje";
  if (daysAgo === 1) return "feito ontem";
  if (daysAgo < 7) return `há ${daysAgo} dias`;
  return "há mais de 7 dias";
}

export default function WorkoutsPage() {
  return (
    <UpgradeGate allowFreeWorkout>
      <WorkoutsContent />
    </UpgradeGate>
  );
}

function WorkoutsContent() {
  const router = useRouter();
  const { activeWorkoutDayId, elapsedSeconds } = useWorkoutSession();
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [todayDay, setTodayDay] = useState<WorkoutDay | null>(null);
  const [sessions, setSessions] = useState<WorkoutSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [activePhase, setActivePhase] = useState<string | null>(null);

  useEffect(() => {
    try {
      const phase = sessionStorage.getItem("wk_phase");
      if (phase && phase !== "done" && phase !== "choose") {
        setActivePhase(phase);
      }
    } catch { /* storage unavailable */ }

    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api
        .get<{ day: WorkoutDay | null }>("/api/v1/workout_plan/today")
        .catch(() => ({ day: null })),
      api
        .get<{ sessions: WorkoutSession[]; total: number }>("/api/v1/workout_sessions?recent=1")
        .catch(() => ({ sessions: [], total: 0 })),
    ]).then(([p, today, history]) => {
      setPlan(p);
      setTodayDay(today?.day ?? null);
      setSessions(history?.sessions ?? []);
    }).finally(() => setLoading(false));
  }, []);

  async function toggleFavorite(dayId: number) {
    if (!plan) return;
    const prev = plan.days.find((d) => d.id === dayId)?.favorited ?? false;
    setPlan((p) =>
      p ? { ...p, days: p.days.map((d) => (d.id === dayId ? { ...d, favorited: !prev } : d)) } : p
    );
    try {
      const resp = await api.patch<{ favorited: boolean }>(
        `/api/v1/workout_days/${dayId}/toggle_favorite`,
        {}
      );
      setPlan((p) =>
        p
          ? { ...p, days: p.days.map((d) => (d.id === dayId ? { ...d, favorited: resp.favorited } : d)) }
          : p
      );
    } catch {
      setPlan((p) =>
        p ? { ...p, days: p.days.map((d) => (d.id === dayId ? { ...d, favorited: prev } : d)) } : p
      );
    }
  }

  if (loading) return <LoadingScreen />;

  const hasActiveSession = !!activeWorkoutDayId && !!activePhase;
  const favoriteDays = plan?.days.filter((d) => d.favorited) ?? [];
  const recommendedId = plan ? recommendedDayId(plan, sessions) : null;
  const activeDayName = plan?.days.find((d) => d.id === activeWorkoutDayId)?.name ?? "Treino";

  const recommended = todayDay ?? plan?.days.find((d) => d.id === recommendedId) ?? null;

  return (
    <div className="min-h-screen px-4 py-6 pb-28" style={{ background: "#0a0f1e" }}>
      <h1 className="text-2xl font-bold text-white">Treinos</h1>

      {/* Active session card */}
      {hasActiveSession ? (
        <div className="mt-4 rounded-2xl border border-primary-500/30 bg-primary-500/10 p-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary-500 text-white text-lg">
              ▶
            </div>
            <div className="flex-1">
              <p className="font-semibold text-primary-400">Treino em andamento</p>
              <p className="text-sm text-primary-500">
                {activeDayName} · {formatElapsed(elapsedSeconds)}
              </p>
            </div>
          </div>
          <button
            onClick={() => router.push("/workout/today")}
            className="mt-3 w-full rounded-full bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600 active:scale-95 transition-transform"
            style={{ boxShadow: "0 0 0 1px rgba(59,130,246,.35), 0 6px 20px rgba(59,130,246,.28)" }}
          >
            Continuar treino
          </button>
        </div>
      ) : recommended ? (
        /* Recommended workout card */
        <div className="mt-4 rounded-2xl border border-primary-500/30 bg-primary-500/10 p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-primary-400">Treino de hoje</p>
          <p className="mt-1 text-lg font-bold text-white">{recommended.name}</p>
          <p className="text-sm text-slate-400">{recommended.exercise_count} exercícios</p>
          {recommended.muscle_groups?.length ? (
            <div className="mt-1.5 flex flex-wrap gap-1">
              {recommended.muscle_groups.slice(0, 3).map((m) => (
                <span
                  key={m}
                  className={`rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[m] ?? "bg-slate-700 text-slate-300"}`}
                >
                  {m}
                </span>
              ))}
            </div>
          ) : null}
          <button
            onClick={() => router.push(`/workout/today?day=${recommended.id}`)}
            className="mt-3 w-full rounded-full bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600 active:scale-95 transition-transform"
            style={{ boxShadow: "0 0 0 1px rgba(59,130,246,.35), 0 6px 20px rgba(59,130,246,.28)" }}
          >
            Iniciar treino
          </button>
        </div>
      ) : null}

      {/* No plan state */}
      {!plan && (
        <div className="mt-4 rounded-2xl border border-dashed border-slate-700 p-6 text-center">
          <p className="text-2xl">🏋️</p>
          <p className="mt-2 font-semibold text-white">Nenhum plano ativo</p>
          <p className="mt-1 text-sm text-slate-400">Crie seu plano personalizado com IA</p>
          <button
            onClick={() => router.push("/plan")}
            className="mt-4 w-full rounded-full bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600"
          >
            Criar meu plano
          </button>
        </div>
      )}

      {/* Meu Plano section */}
      {plan && (
        <section className="mt-8">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Meu Plano
          </h2>
          <div className="mt-3 space-y-3">
            {plan.days.map((day, idx) => (
              <WorkoutDayCard
                key={day.id}
                day={day}
                idx={idx}
                sessions={sessions}
                isRecommended={day.id === recommendedId}
                onView={() => router.push(`/workout/today?day=${day.id}`)}
                onStart={() => router.push(`/workout/today?day=${day.id}`)}
                onToggleFavorite={() => toggleFavorite(day.id)}
              />
            ))}
          </div>
        </section>
      )}

      {/* Favoritos section */}
      {favoriteDays.length > 0 && (
        <section className="mt-8">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Favoritos ❤️
          </h2>
          <div className="mt-3 space-y-3">
            {favoriteDays.map((day) => {
              const idx = plan!.days.findIndex((d) => d.id === day.id);
              return (
                <WorkoutDayCard
                  key={day.id}
                  day={day}
                  idx={idx}
                  sessions={sessions}
                  isRecommended={false}
                  onView={() => router.push(`/workout/today?day=${day.id}`)}
                  onStart={() => router.push(`/workout/today?day=${day.id}`)}
                  onToggleFavorite={() => toggleFavorite(day.id)}
                />
              );
            })}
          </div>
        </section>
      )}

      {/* Histórico section */}
      <section className="mt-8">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Histórico
          </h2>
          <Link href="/history" className="text-xs font-medium text-primary-400 hover:text-primary-300">
            Ver tudo →
          </Link>
        </div>
        {sessions.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">Nenhum treino realizado ainda.</p>
        ) : (
          <div className="mt-3 space-y-2">
            {sessions.slice(0, 5).map((session) => (
              <div
                key={session.id}
                className="flex items-center justify-between rounded-xl border border-slate-800 bg-slate-900 p-4"
              >
                <div className="min-w-0">
                  <p className="truncate font-medium text-white">
                    {session.workout_day_name}
                  </p>
                  <p className="text-xs text-slate-500">
                    {relativeDate(session.completed_at)} · {session.duration_minutes} min
                    {session.fatigue_level ? ` · cansaço ${session.fatigue_level}/5` : ""}
                  </p>
                </div>
                <button
                  onClick={() => router.push(`/workout/today?day=${session.workout_day_id}`)}
                  className="ml-3 shrink-0 rounded-full bg-primary-500/15 px-3 py-1.5 text-xs font-semibold text-primary-400 hover:bg-primary-500/25"
                >
                  Repetir
                </button>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Actions */}
      <section className="mt-8 space-y-3">
        <button
          onClick={() => router.push("/plan?wizard=1")}
          className="flex w-full items-center justify-between rounded-xl border border-slate-800 bg-slate-900 p-4"
        >
          <div className="flex items-center gap-3">
            <span className="text-2xl">✨</span>
            <div className="text-left">
              <p className="font-semibold text-white">Replanejar com IA</p>
              <p className="text-xs text-slate-500">Gere um novo plano baseado no seu perfil</p>
            </div>
          </div>
          <span className="text-lg text-slate-600">›</span>
        </button>
      </section>
    </div>
  );
}

function WorkoutDayCard({
  day,
  idx,
  sessions,
  isRecommended,
  onView,
  onStart,
  onToggleFavorite,
}: {
  day: WorkoutDay;
  idx: number;
  sessions: WorkoutSession[];
  isRecommended: boolean;
  onView: () => void;
  onStart: () => void;
  onToggleFavorite: () => void;
}) {
  const lastSession = lastSessionForDay(sessions, day.id);

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onView}
      onKeyDown={(e) => e.key === "Enter" && onView()}
      className={`cursor-pointer rounded-xl border p-4 transition-opacity active:opacity-70 ${
        isRecommended
          ? "border-primary-500/40 bg-primary-500/10"
          : "border-slate-800 bg-slate-900"
      }`}
    >
      <div className="flex items-center gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary-500/15 font-bold text-primary-400">
          {LETTERS[idx] ?? idx + 1}
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <p className="truncate font-semibold text-white">{day.name}</p>
            {isRecommended && (
              <span className="shrink-0 rounded-full bg-primary-500 px-2 py-0.5 text-xs font-semibold text-white">
                Hoje
              </span>
            )}
          </div>
          <p className="text-xs text-slate-500">{day.exercise_count} exercícios</p>
          {day.muscle_groups?.length ? (
            <div className="mt-1 flex flex-wrap gap-1">
              {day.muscle_groups.slice(0, 2).map((m) => (
                <span
                  key={m}
                  className={`rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[m] ?? "bg-slate-700 text-slate-300"}`}
                >
                  {m}
                </span>
              ))}
            </div>
          ) : null}
          <p className="mt-0.5 text-xs text-slate-600">
            {lastSession ? relativeDate(lastSession.completed_at) : "nunca executado"}
          </p>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-2">
          <button
            onClick={(e) => {
              e.stopPropagation();
              onToggleFavorite();
            }}
            className="text-xl leading-none transition-transform active:scale-90"
            aria-label={day.favorited ? "Remover dos favoritos" : "Adicionar aos favoritos"}
          >
            {day.favorited ? "❤️" : "🤍"}
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation();
              onStart();
            }}
            className="rounded-full bg-primary-500 px-3 py-1.5 text-xs font-semibold text-white hover:bg-primary-600 active:scale-95 transition-transform"
          >
            Iniciar
          </button>
        </div>
      </div>
    </div>
  );
}

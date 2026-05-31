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
  chest: "bg-red-100 text-red-700",
  back: "bg-blue-100 text-blue-700",
  shoulders: "bg-purple-100 text-purple-700",
  biceps: "bg-yellow-100 text-yellow-700",
  triceps: "bg-orange-100 text-orange-700",
  legs: "bg-green-100 text-green-700",
  core: "bg-teal-100 text-teal-700",
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
    <div className="min-h-screen bg-white px-4 py-6 pb-28 dark:bg-gray-950">
      <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-50">Treinos</h1>

      {/* Active session card */}
      {hasActiveSession ? (
        <div className="mt-4 rounded-2xl border border-primary-200 bg-primary-50 p-4 dark:border-primary-900 dark:bg-primary-950/20">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary-500 text-white text-lg">
              ▶
            </div>
            <div className="flex-1">
              <p className="font-semibold text-primary-700 dark:text-primary-300">Treino em andamento</p>
              <p className="text-sm text-primary-500">
                {activeDayName} · {formatElapsed(elapsedSeconds)}
              </p>
            </div>
          </div>
          <button
            onClick={() => router.push("/workout/today")}
            className="mt-3 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600 active:scale-95 transition-transform"
          >
            Continuar treino
          </button>
        </div>
      ) : recommended ? (
        /* Recommended workout card */
        <div className="mt-4 rounded-2xl border border-primary-200 bg-gradient-to-br from-primary-50 to-blue-50 p-4 dark:border-primary-900 dark:from-primary-950/20 dark:to-blue-950/20">
          <p className="text-xs font-semibold uppercase tracking-wide text-primary-500">Treino de hoje</p>
          <p className="mt-1 text-lg font-bold text-gray-900 dark:text-gray-50">{recommended.name}</p>
          <p className="text-sm text-gray-500">{recommended.exercise_count} exercícios</p>
          {recommended.muscle_groups?.length ? (
            <div className="mt-1.5 flex flex-wrap gap-1">
              {recommended.muscle_groups.slice(0, 3).map((m) => (
                <span
                  key={m}
                  className={`rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[m] ?? "bg-gray-100 text-gray-600"}`}
                >
                  {m}
                </span>
              ))}
            </div>
          ) : null}
          <button
            onClick={() => router.push(`/workout/today?day=${recommended.id}`)}
            className="mt-3 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600 active:scale-95 transition-transform"
          >
            Iniciar treino
          </button>
        </div>
      ) : null}

      {/* No plan state */}
      {!plan && (
        <div className="mt-4 rounded-2xl border border-dashed border-gray-200 p-6 text-center dark:border-gray-700">
          <p className="text-2xl">🏋️</p>
          <p className="mt-2 font-semibold text-gray-700 dark:text-gray-300">Nenhum plano ativo</p>
          <p className="mt-1 text-sm text-gray-500">Crie seu plano personalizado com IA</p>
          <button
            onClick={() => router.push("/plan")}
            className="mt-4 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600"
          >
            Criar meu plano
          </button>
        </div>
      )}

      {/* Meu Plano section */}
      {plan && (
        <section className="mt-8">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
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
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
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
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            Histórico
          </h2>
          <Link href="/history" className="text-xs font-medium text-primary-500 hover:text-primary-600">
            Ver tudo →
          </Link>
        </div>
        {sessions.length === 0 ? (
          <p className="mt-3 text-sm text-gray-400">Nenhum treino realizado ainda.</p>
        ) : (
          <div className="mt-3 space-y-2">
            {sessions.slice(0, 5).map((session) => (
              <div
                key={session.id}
                className="flex items-center justify-between rounded-xl border border-gray-100 bg-white p-4 dark:border-gray-800 dark:bg-gray-900"
              >
                <div className="min-w-0">
                  <p className="truncate font-medium text-gray-900 dark:text-gray-50">
                    {session.workout_day_name}
                  </p>
                  <p className="text-xs text-gray-500">
                    {relativeDate(session.completed_at)} · {session.duration_minutes} min
                    {session.fatigue_level ? ` · cansaço ${session.fatigue_level}/5` : ""}
                  </p>
                </div>
                <button
                  onClick={() => router.push(`/workout/today?day=${session.workout_day_id}`)}
                  className="ml-3 shrink-0 rounded-full bg-primary-50 px-3 py-1.5 text-xs font-semibold text-primary-600 hover:bg-primary-100 dark:bg-primary-950/40 dark:text-primary-400"
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
          className="flex w-full items-center justify-between rounded-xl border border-gray-100 bg-white p-4 dark:border-gray-800 dark:bg-gray-900"
        >
          <div className="flex items-center gap-3">
            <span className="text-2xl">✨</span>
            <div className="text-left">
              <p className="font-semibold text-gray-900 dark:text-gray-50">Replanejar com IA</p>
              <p className="text-xs text-gray-500">Gere um novo plano baseado no seu perfil</p>
            </div>
          </div>
          <span className="text-lg text-gray-400">›</span>
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
  onStart,
  onToggleFavorite,
}: {
  day: WorkoutDay;
  idx: number;
  sessions: WorkoutSession[];
  isRecommended: boolean;
  onStart: () => void;
  onToggleFavorite: () => void;
}) {
  const lastSession = lastSessionForDay(sessions, day.id);

  return (
    <div
      className={`rounded-xl border p-4 ${
        isRecommended
          ? "border-primary-200 bg-primary-50 dark:border-primary-800 dark:bg-primary-950/20"
          : "border-gray-100 bg-white dark:border-gray-800 dark:bg-gray-900"
      }`}
    >
      <div className="flex items-center gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary-50 font-bold text-primary-600 dark:bg-primary-950/40">
          {LETTERS[idx] ?? idx + 1}
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <p className="truncate font-semibold text-gray-900 dark:text-gray-50">{day.name}</p>
            {isRecommended && (
              <span className="shrink-0 rounded-full bg-primary-500 px-2 py-0.5 text-xs font-semibold text-white">
                Hoje
              </span>
            )}
          </div>
          <p className="text-xs text-gray-500">{day.exercise_count} exercícios</p>
          {day.muscle_groups?.length ? (
            <div className="mt-1 flex flex-wrap gap-1">
              {day.muscle_groups.slice(0, 2).map((m) => (
                <span
                  key={m}
                  className={`rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[m] ?? "bg-gray-100 text-gray-600"}`}
                >
                  {m}
                </span>
              ))}
            </div>
          ) : null}
          <p className="mt-0.5 text-xs text-gray-400">
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
            onClick={onStart}
            className="rounded-full bg-primary-500 px-3 py-1.5 text-xs font-semibold text-white hover:bg-primary-600 active:scale-95 transition-transform"
          >
            Iniciar
          </button>
        </div>
      </div>
    </div>
  );
}

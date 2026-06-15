"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { UpgradeGate } from "@/shared/components/upgrade-gate";
import { useWorkoutSession, formatElapsed } from "@/features/workout/workout-session-context";
import { AITrainerBubble } from "@/shared/components/ai-trainer";
import { AgentOrb } from "@/shared/components/agent-orb";
import { WorkoutRow } from "@/shared/components/workout/workout-row";
import { RenameWorkoutModal } from "@/shared/components/workout/rename-workout-modal";
import "@/shared/components/workout/workout-ui.css";
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

function workoutDisplayName(day: WorkoutDay, idx: number): string {
  return day.custom_name || day.name || `Treino ${LETTERS[idx] ?? idx + 1}`;
}

function formatLastCompleted(dateStr: string | null | undefined): string | undefined {
  if (!dateStr) return undefined;
  const daysAgo = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (daysAgo === 0) return "Última vez: hoje";
  if (daysAgo === 1) return "Última vez: ontem";
  if (daysAgo < 7) return `Última vez: há ${daysAgo} dias`;
  return `Última vez: ${new Date(dateStr).toLocaleDateString("pt-BR")}`;
}

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
  const [renamingDay, setRenamingDay] = useState<WorkoutDay | null>(null);

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

  async function handleRename(dayId: number, customName: string) {
    const resp = await api.patch<{ id: number; custom_name: string | null }>(
      `/api/v1/workout_days/${dayId}/rename`,
      { custom_name: customName }
    );
    setPlan((p) =>
      p ? { ...p, days: p.days.map((d) => d.id === dayId ? { ...d, custom_name: resp.custom_name } : d) } : p
    );
  }

  const mostExecutedDays = useMemo(() => {
    if (!plan?.days || !sessions.length) return [];
    const freq: Record<number, number> = {};
    sessions.forEach((s) => { freq[s.workout_day_id] = (freq[s.workout_day_id] ?? 0) + 1; });
    return [...plan.days]
      .filter((d) => d.id !== null && (freq[d.id] ?? 0) > 0)
      .sort((a, b) => (freq[b.id!] ?? 0) - (freq[a.id!] ?? 0))
      .slice(0, 3);
  }, [plan?.days, sessions]);

  const lastExecutedDay = useMemo(() => {
    if (!plan?.days || !sessions.length) return null;
    const lastSession = [...sessions].sort((a, b) => new Date(b.completed_at).getTime() - new Date(a.completed_at).getTime())[0];
    return plan.days.find((d) => d.id === lastSession?.workout_day_id) ?? null;
  }, [plan?.days, sessions]);

  if (loading) return <LoadingScreen />;

  const hasActiveSession = !!activeWorkoutDayId && !!activePhase;
  const favoriteDays = plan?.days.filter((d) => d.favorited) ?? [];
  const recommendedId = plan ? recommendedDayId(plan, sessions) : null;
  const activeDayName = plan?.days.find((d) => d.id === activeWorkoutDayId)?.name ?? "Treino";

  const recommended = todayDay ?? plan?.days.find((d) => d.id === recommendedId) ?? null;

  return (
    <div style={{ minHeight: "100svh", background: "var(--bg)", color: "var(--text)", padding: "52px 20px 100px" }}>
      <div style={{ marginBottom: 20 }}>
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: 26, fontWeight: 700, letterSpacing: "-0.02em", margin: "0 0 12px" }}>Treinos</h1>
        <div style={{ display: "flex", gap: 8 }}>
          <Link
            href="/workout/quick"
            style={{
              flex: 1, display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 6,
              background: "var(--primary-soft)", color: "var(--primary)",
              borderRadius: "var(--r-pill)", padding: "10px 14px",
              fontSize: 13, fontWeight: 700, textDecoration: "none",
              border: "1px solid oklch(0.685 var(--accent-c, 0.17) var(--accent-h, 258) / .25)",
            }}
          >
            ⚡ Treino Rápido
          </Link>
          <button
            onClick={() => router.push("/plan?wizard=1")}
            style={{
              flex: 1, display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 6,
              background: "var(--surface)", color: "var(--text)",
              borderRadius: "var(--r-pill)", padding: "10px 14px",
              fontSize: 13, fontWeight: 700,
              border: "1px solid var(--border)", cursor: "pointer",
            }}
          >
            ✨ Replanejar com IA
          </button>
        </div>
      </div>

      {/* Active session card */}
      {hasActiveSession ? (
        <div style={{ marginBottom: 14, background: "var(--primary-soft)", border: "1px solid oklch(0.685 var(--accent-c, 0.17) var(--accent-h, 258) / .35)", borderRadius: "var(--r-lg)", padding: 18 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 14 }}>
            <div style={{ width: 40, height: 40, borderRadius: "50%", background: "var(--primary)", color: "var(--on-primary)", display: "grid", placeItems: "center", fontSize: 18, flexShrink: 0 }}>▶</div>
            <div>
              <p style={{ fontWeight: 700, color: "var(--primary)", margin: 0 }}>Treino em andamento</p>
              <p style={{ fontSize: 13, color: "var(--text-muted)", margin: 0 }}>{activeDayName} · {formatElapsed(elapsedSeconds)}</p>
            </div>
          </div>
          <button
            onClick={() => router.push("/workout/today")}
            style={{
              width: "100%", borderRadius: "var(--r-pill)", padding: "14px",
              background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
              color: "var(--on-primary)", fontWeight: 700, fontSize: 15, border: 0,
              cursor: "pointer", boxShadow: "var(--glow)",
            }}
          >
            Continuar treino
          </button>
        </div>
      ) : recommended ? (
        <div style={{ marginBottom: 14, background: "var(--primary-soft)", border: "1px solid oklch(0.685 var(--accent-c, 0.17) var(--accent-h, 258) / .3)", borderRadius: "var(--r-lg)", padding: 18 }}>
          <p className="eyebrow" style={{ color: "var(--primary)", marginBottom: 6 }}>Treino de hoje</p>
          <p style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: "0 0 4px", letterSpacing: "-0.015em" }}>{recommended.name}</p>
          <p style={{ fontSize: 13, color: "var(--text-muted)", margin: "0 0 10px" }}>{recommended.exercise_count} exercícios</p>
          {recommended.muscle_groups?.length ? (
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 14 }}>
              {recommended.muscle_groups.slice(0, 3).map((m) => (
                <span key={m} className="tag-chip muscle">{m}</span>
              ))}
            </div>
          ) : null}
          <button
            onClick={() => router.push(`/workout/today?day=${recommended.id}`)}
            style={{
              width: "100%", borderRadius: "var(--r-pill)", padding: "14px",
              background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
              color: "var(--on-primary)", fontWeight: 700, fontSize: 15, border: 0,
              cursor: "pointer", boxShadow: "var(--glow)",
            }}
          >
            Iniciar treino
          </button>
        </div>
      ) : null}

      {/* No plan state */}
      {!plan && (
        <div style={{ border: "1.5px dashed var(--border)", borderRadius: "var(--r-lg)", padding: 24, textAlign: "center", marginBottom: 14 }}>
          <p style={{ fontSize: 28, margin: "0 0 8px" }}>🏋️</p>
          <p style={{ fontWeight: 700, margin: "0 0 4px" }}>Nenhum plano ativo</p>
          <p style={{ fontSize: 13, color: "var(--text-muted)", margin: "0 0 16px" }}>Crie seu plano personalizado com IA</p>
          <button
            onClick={() => router.push("/plan")}
            style={{ width: "100%", borderRadius: "var(--r-pill)", padding: "14px", background: "linear-gradient(180deg, var(--primary), var(--primary-2))", color: "var(--on-primary)", fontWeight: 700, border: 0, cursor: "pointer" }}
          >
            Criar meu plano
          </button>
        </div>
      )}

      {/* AI rationale card */}
      {plan?.ai_rationale && (
        <div style={{ background: "var(--primary-soft)", border: "1px solid oklch(0.685 var(--accent-c, 0.17) var(--accent-h, 258) / .28)", borderRadius: "var(--r-lg)", padding: "14px 18px", marginBottom: 14 }}>
          <p className="eyebrow" style={{ color: "var(--primary)", marginBottom: 6 }}>Por que este plano?</p>
          <p style={{ fontSize: 14, color: "var(--text-muted)", margin: 0, lineHeight: 1.5 }}>{plan.ai_rationale}</p>
        </div>
      )}

      {/* Meu Plano section */}
      {plan && (
        <section style={{ marginTop: 28 }}>
          <p className="eyebrow" style={{ marginBottom: 10 }}>Meu Plano</p>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {plan.days.map((day, idx) => (
              <WorkoutRow
                key={day.id}
                badge={LETTERS[idx] ?? String(idx + 1)}
                name={workoutDisplayName(day, idx)}
                sub={formatLastCompleted(day.last_completed_at) ?? (day.exercise_count ? `${day.exercise_count} exercícios` : undefined)}
                tags={day.muscle_groups?.slice(0, 2)}
                favorited={day.favorited}
                onFavorite={() => day.id !== null && toggleFavorite(day.id)}
                onRename={() => setRenamingDay(day)}
                onClick={() => router.push(`/workout/today?day=${day.id}`)}
              />
            ))}
          </div>
        </section>
      )}

      {/* Favoritos section — enhanced */}
      <section style={{ marginTop: 28 }}>
        <p className="eyebrow" style={{ marginBottom: 10 }}>Favoritos & Mais Usados</p>

        {favoriteDays.length === 0 && mostExecutedDays.length === 0 && lastExecutedDay === null ? (
          <div style={{ display: "flex", alignItems: "flex-start", gap: 12, background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--r-lg)", padding: 16 }}>
            <AgentOrb size="card" glyph />
            <AITrainerBubble
              message="Marque treinos como favoritos para acessá-los rapidamente aqui. Após treinar, seus mais usados também aparecem."
              mood="speaking"
              show
              side="left"
            />
          </div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
            {/* ⭐ Favoritos */}
            {favoriteDays.length > 0 && (
              <div>
                <p style={{ fontSize: 11.5, fontWeight: 700, color: "var(--text-dim)", marginBottom: 8 }}>⭐ Favoritos</p>
                <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                  {favoriteDays.map((day) => {
                    const idx = plan!.days.findIndex((d) => d.id === day.id);
                    return (
                      <WorkoutRow
                        key={day.id}
                        badge={LETTERS[idx] ?? String(idx + 1)}
                        name={workoutDisplayName(day, idx)}
                        sub={formatLastCompleted(day.last_completed_at) ?? (day.exercise_count ? `${day.exercise_count} exercícios` : undefined)}
                        tags={day.muscle_groups?.slice(0, 2)}
                        favorited={day.favorited}
                        onFavorite={() => day.id !== null && toggleFavorite(day.id)}
                        onRename={() => setRenamingDay(day)}
                        onClick={() => router.push(`/workout/today?day=${day.id}`)}
                      />
                    );
                  })}
                </div>
              </div>
            )}

            {/* 🔁 Mais executados */}
            {mostExecutedDays.length > 0 && (
              <div>
                <p style={{ fontSize: 11.5, fontWeight: 700, color: "var(--text-dim)", marginBottom: 8 }}>🔁 Mais executados</p>
                <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                  {mostExecutedDays.map((day) => {
                    const idx = plan!.days.findIndex((d) => d.id === day.id);
                    return (
                      <WorkoutRow
                        key={`freq-${day.id}`}
                        badge={LETTERS[idx] ?? String(idx + 1)}
                        name={workoutDisplayName(day, idx)}
                        sub={formatLastCompleted(day.last_completed_at) ?? (day.exercise_count ? `${day.exercise_count} exercícios` : undefined)}
                        tags={day.muscle_groups?.slice(0, 2)}
                        favorited={day.favorited}
                        onFavorite={() => day.id !== null && toggleFavorite(day.id)}
                        onRename={() => setRenamingDay(day)}
                        onClick={() => router.push(`/workout/today?day=${day.id}`)}
                      />
                    );
                  })}
                </div>
              </div>
            )}

            {/* ⏱ Último executado */}
            {lastExecutedDay && (
              <div>
                <p style={{ fontSize: 11.5, fontWeight: 700, color: "var(--text-dim)", marginBottom: 8 }}>⏱ Último executado</p>
                <WorkoutRow
                  badge={LETTERS[plan!.days.findIndex((d) => d.id === lastExecutedDay.id)] ?? "?"}
                  name={workoutDisplayName(lastExecutedDay, plan!.days.findIndex((d) => d.id === lastExecutedDay.id))}
                  sub={formatLastCompleted(lastExecutedDay.last_completed_at) ?? (lastExecutedDay.exercise_count ? `${lastExecutedDay.exercise_count} exercícios` : undefined)}
                  tags={lastExecutedDay.muscle_groups?.slice(0, 2)}
                  favorited={lastExecutedDay.favorited}
                  onFavorite={() => lastExecutedDay.id !== null && toggleFavorite(lastExecutedDay.id)}
                  onRename={() => setRenamingDay(lastExecutedDay)}
                  onClick={() => router.push(`/workout/today?day=${lastExecutedDay.id}`)}
                />
              </div>
            )}
          </div>
        )}
      </section>

      {/* Histórico section */}
      <section style={{ marginTop: 28 }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 10 }}>
          <p className="eyebrow">Histórico recente</p>
          <Link href="/history" style={{ fontSize: 13, fontWeight: 700, color: "var(--primary)", textDecoration: "none" }}>Ver tudo →</Link>
        </div>
        {sessions.length === 0 ? (
          <p style={{ fontSize: 14, color: "var(--text-dim)" }}>Nenhum treino realizado ainda.</p>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {sessions.slice(0, 5).map((session) => (
              <div
                key={session.id}
                style={{ display: "flex", alignItems: "center", justifyContent: "space-between", background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--r-md)", padding: "12px 14px" }}
              >
                <div style={{ minWidth: 0, flex: 1 }}>
                  <p style={{ fontWeight: 700, margin: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{session.workout_day_name}</p>
                  <p style={{ fontSize: 12, color: "var(--text-dim)", margin: 0 }}>
                    {relativeDate(session.completed_at)} · {session.duration_minutes} min
                    {session.fatigue_level ? ` · cansaço ${session.fatigue_level}/5` : ""}
                  </p>
                </div>
                <button
                  onClick={() => router.push(`/workout/today?day=${session.workout_day_id}`)}
                  style={{ marginLeft: 12, flexShrink: 0, borderRadius: "var(--r-pill)", background: "var(--primary-soft)", color: "var(--primary)", border: 0, padding: "7px 14px", fontSize: 12, fontWeight: 700, cursor: "pointer" }}
                >
                  Repetir
                </button>
              </div>
            ))}
          </div>
        )}
      </section>

      <RenameWorkoutModal
        open={!!renamingDay}
        currentName={renamingDay?.custom_name ?? ""}
        defaultName={renamingDay ? (renamingDay.name || `Treino ${LETTERS[plan!.days.findIndex((d) => d.id === renamingDay.id)] ?? ""}`) : ""}
        onSave={(name) => renamingDay?.id != null ? handleRename(renamingDay.id, name) : Promise.resolve()}
        onClose={() => setRenamingDay(null)}
      />
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
  highlight = false,
}: {
  day: WorkoutDay;
  idx: number;
  sessions: WorkoutSession[];
  isRecommended: boolean;
  onView: () => void;
  onStart: () => void;
  onToggleFavorite: () => void;
  highlight?: boolean;
}) {
  const lastSession = day.id !== null ? lastSessionForDay(sessions, day.id) : null;

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onView}
      onKeyDown={(e) => e.key === "Enter" && onView()}
      className={`cursor-pointer rounded-xl border p-4 transition-opacity active:opacity-70 ${
        isRecommended
          ? "border-primary-500/40 bg-primary-500/10"
          : highlight
          ? "border-primary-800/60 bg-slate-900"
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
            {day.favorited ? "⭐" : "☆"}
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

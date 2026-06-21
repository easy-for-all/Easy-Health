"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { api } from "@/shared/lib/api";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { HeroWorkout } from "@/shared/components/workout/hero-workout";
import { WorkoutDoneCard } from "@/shared/components/workout/workout-done-card";
import { InsightCard } from "@/shared/components/workout/insight-card";
import { StreakCard } from "@/shared/components/workout/streak-card";
import { WorkoutRow } from "@/shared/components/workout/workout-row";
import type { WorkoutPlan, WorkoutDay, WorkoutSession } from "@/shared/types/workout";

type PersonalRecord = {
  exercise_id: number;
  exercise_name: string;
  max_weight_kg: number;
  achieved_at: string;
};

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const DAYS_PT = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"];

function getTodayLabel(): string {
  const d = new Date();
  return DAYS_PT[d.getDay()]?.toUpperCase() ?? "HOJE";
}

function estimateMinutes(exerciseCount: number): number {
  return Math.round((exerciseCount * 4 + 10) / 5) * 5;
}

function completedWeekDayIndices(dates: string[]): number[] {
  const now = new Date();
  const indices = new Set<number>();
  dates.forEach((iso) => {
    const d = new Date(iso);
    if (d <= now) {
      indices.add(d.getDay()); // 0=Sun..6=Sat — matches Sun-first streak-card labels
    }
  });
  return [...indices];
}

export default function DashboardPage() {
  const { user } = useAuth();
  const router = useRouter();
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [streak, setStreak] = useState(0);
  const [weeklySessions, setWeeklySessions] = useState(0);
  const [weeklyGoal, setWeeklyGoal] = useState(3);
  const [weeklySessionDates, setWeeklySessionDates] = useState<string[]>([]);
  const [aiInsight, setAiInsight] = useState<string | null>(null);
  const [aiActionType, setAiActionType] = useState<string | null>(null);
  const [aiDismissed, setAiDismissed] = useState(false);
  const [todaySession, setTodaySession] = useState<WorkoutSession | null>(null);
  const [loading, setLoading] = useState(true);
  const [noProfile, setNoProfile] = useState(false);
  const [dominantModality, setDominantModality] = useState<string | null>(null);
  const [modalityStats, setModalityStats] = useState<Record<string, number | null> | null>(null);
  const [personalRecords, setPersonalRecords] = useState<PersonalRecord[]>([]);
  const [fatigueAvg, setFatigueAvg] = useState<number | null>(null);
  const [fatigueTrend, setFatigueTrend] = useState<number | null>(null);
  const [suggestDeload, setSuggestDeload] = useState(false);

  useEffect(() => {
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "home" });
  }, []);

  useEffect(() => {
    function loadData() {
      return Promise.all([
        api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
        api.get<{ streak: number; total_sessions: number; weekly_sessions: number; weekly_goal: number; weekly_session_dates?: string[]; dominant_modality?: string; modality_stats?: Record<string, number | null>; fatigue_avg?: number | null; fatigue_trend?: number | null; suggest_deload?: boolean }>(
          "/api/v1/workout_sessions/stats"
        ).catch(() => null),
        api.get<{ recommendations?: { action: string; suggestion: string; reason: string; priority: string }[] }>("/api/v1/ai_agents/personal_trainer").catch(() => null),
        api.get<WorkoutSession | Record<string, never>>("/api/v1/workout_sessions/today").catch(() => null),
        api.get<PersonalRecord[]>("/api/v1/workout_sessions/personal_records").catch(() => []),
      ]).then(([p, s, ai, todayRaw, prs]) => {
        if (!p) setNoProfile(true);
        setPlan(p);
        setStreak(s?.streak ?? 0);
        setWeeklySessions(s?.weekly_sessions ?? 0);
        setWeeklyGoal(s?.weekly_goal ?? 3);
        setWeeklySessionDates(s?.weekly_session_dates ?? []);
        if (s?.dominant_modality) setDominantModality(s.dominant_modality);
        if (s?.modality_stats) setModalityStats(s.modality_stats as Record<string, number | null>);
        setFatigueAvg(s?.fatigue_avg ?? null);
        setFatigueTrend(s?.fatigue_trend ?? null);
        setSuggestDeload(s?.suggest_deload ?? false);
        const topRec = ai?.recommendations?.find((r) => r.priority === "high") ?? ai?.recommendations?.[0];
        if (topRec?.suggestion) {
          setAiInsight(`${topRec.suggestion}${topRec.reason ? ` <b>—</b> ${topRec.reason}` : ""}`);
          setAiActionType(topRec.action ?? null);
        }
        if (todayRaw && "id" in todayRaw) {
          setTodaySession(todayRaw as WorkoutSession);
        }
        if (prs && prs.length > 0) setPersonalRecords(prs);
      }).finally(() => setLoading(false));
    }

    // Refetch immediately if returning from a just-completed workout
    try {
      if (sessionStorage.getItem("dashboard_stale") === "1") {
        sessionStorage.removeItem("dashboard_stale");
      }
    } catch { /* ok */ }

    loadData();
  }, []);

  if (loading) return <LoadingScreen />;

  if (noProfile) {
    return (
      <div
        style={{
          display: "flex", flexDirection: "column", alignItems: "center",
          justifyContent: "center", minHeight: "100svh", padding: "0 20px", gap: 16,
        }}
      >
        <p style={{ color: "var(--text-muted)", textAlign: "center", margin: 0 }}>
          Complete seu perfil para ver seu plano.
        </p>
        <a
          href="/onboarding"
          style={{
            background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
            color: "var(--on-primary)", borderRadius: "var(--r-pill)",
            padding: "14px 24px", fontWeight: 700, fontSize: 15,
            textDecoration: "none", boxShadow: "var(--glow)",
          }}
        >
          Completar perfil
        </a>
      </div>
    );
  }

  const todayDay = plan?.days?.[0];
  const todayLabel = getTodayLabel();

  return (
    <div
      style={{
        minHeight: "100svh",
        background: "var(--bg)",
        padding: "0 0 100px",
      }}
    >
      {/* Top bar */}
      <header
        style={{
          display: "flex", alignItems: "center", justifyContent: "space-between",
          padding: "52px 20px 8px",
        }}
      >
        <div>
          <p
            className="eyebrow"
            style={{ color: "var(--text-dim)", marginBottom: 2 }}
          >
            {todayLabel}
          </p>
          <h1
            style={{
              fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 700,
              letterSpacing: "-0.01em", margin: 0, color: "var(--text)",
            }}
          >
            Olá, {user?.name?.split(" ")[0] ?? "atleta"} 👋
          </h1>
        </div>

        {/* Avatar placeholder */}
        <div
          style={{
            width: 40, height: 40, borderRadius: "50%",
            background: "var(--primary-soft)",
            border: "1px solid var(--border)",
            display: "flex", alignItems: "center", justifyContent: "center",
            fontFamily: "var(--font-display)", fontWeight: 700,
            fontSize: 16, color: "var(--primary)",
          }}
        >
          {user?.name?.[0]?.toUpperCase() ?? "U"}
        </div>
      </header>

      {/* Stagger entrance */}
      <div
        style={{ padding: "8px 20px 0", display: "flex", flexDirection: "column", gap: 14 }}
      >
        {/* Hero — treino do dia ou card de treino realizado */}
        {todaySession ? (
          <WorkoutDoneCard session={todaySession} suggestedDay={todayDay} />
        ) : (
          <HeroWorkout
            dayLabel={`${todayLabel} · TREINO`}
            workoutName={todayDay ? (todayDay.custom_name || todayDay.name) : "Treinar agora"}
            workoutSub={todayDay ? undefined : `${plan?.days?.length ?? 0} treinos no plano`}
            muscleGroups={todayDay?.muscle_groups}
            exerciseCount={todayDay?.exercise_count}
            estimatedMin={todayDay?.exercise_count ? estimateMinutes(todayDay.exercise_count) : undefined}
            href={todayDay ? `/workout/today?day=${todayDay.id}` : "/workout/today"}
          />
        )}

        {/* AI Insight */}
        {aiInsight && !aiDismissed && (
          <InsightCard
            text={aiInsight}
            onDismiss={() => setAiDismissed(true)}
            actionLabel={
              aiActionType === "deload" ? "Ver treino rápido →" :
              aiActionType === "progressao" || aiActionType === "aumentar_peso" || aiActionType === "reduzir_peso" ? "Ver minha evolução →" :
              undefined
            }
            actionHref={
              aiActionType === "deload" ? "/workout/quick" :
              aiActionType === "progressao" || aiActionType === "aumentar_peso" || aiActionType === "reduzir_peso" ? "/history" :
              undefined
            }
          />
        )}

        {/* Streak */}
        <StreakCard
          streak={streak}
          weeklySessions={weeklySessions}
          weeklyGoal={weeklyGoal}
          completedDayIndices={completedWeekDayIndices(weeklySessionDates)}
        />

        {/* Fadiga e recuperação */}
        {fatigueAvg !== null && <FatigueCard avg={fatigueAvg} trend={fatigueTrend} deload={suggestDeload} />}

        {/* Modality metrics card */}
        {modalityStats && dominantModality && <ModalityMetricsCard modality={dominantModality} stats={modalityStats} />}

        {/* Personal Records */}
        {personalRecords.length > 0 && <PersonalRecordsBlock records={personalRecords.slice(0, 3)} />}

        {/* Workout list */}
        {plan?.days && plan.days.length > 0 && (
          <section>
            <p
              className="eyebrow"
              style={{ marginBottom: 10, color: "var(--text-dim)" }}
            >
              Seu plano
            </p>
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {plan.days.map((day: WorkoutDay, idx: number) => (
                <WorkoutRow
                  key={day.id}
                  badge={LETTERS[idx] ?? String(idx + 1)}
                  name={day.custom_name || day.name || `Treino ${LETTERS[idx] ?? idx + 1}`}
                  sub={day.exercise_count ? `${day.exercise_count} exercícios` : undefined}
                  tags={day.muscle_groups?.slice(0, 2)}
                  onClick={() => router.push(`/workout/today?day=${day.id}`)}
                />
              ))}
            </div>
          </section>
        )}

        {/* Empty plan state */}
        {(!plan?.days || plan.days.length === 0) && (
          <div
            style={{
              border: "1.5px dashed var(--border)",
              borderRadius: "var(--r-lg)",
              padding: "24px",
              textAlign: "center",
            }}
          >
            <p style={{ color: "var(--text-muted)", marginBottom: 14, fontSize: 14 }}>
              Nenhum treino cadastrado ainda.
            </p>
            <a
              href="/plan"
              style={{
                background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
                color: "var(--on-primary)", borderRadius: "var(--r-pill)",
                padding: "12px 20px", fontWeight: 700, fontSize: 14,
                textDecoration: "none", display: "inline-block",
              }}
            >
              Criar plano com IA
            </a>
          </div>
        )}

        {/* Quick links */}
        <div style={{ display: "flex", gap: 10 }}>
          <a
            href="/workout/quick"
            style={{
              flex: 1, display: "flex", alignItems: "center", justifyContent: "center",
              gap: 6, borderRadius: "var(--r-md)", padding: "13px",
              background: "var(--primary-soft)",
              border: "1px solid oklch(0.685 var(--accent-c, 0.17) var(--accent-h, 258) / .25)",
              color: "var(--primary)", fontWeight: 700, fontSize: 14,
              textDecoration: "none",
            }}
          >
            ⚡ Treino Rápido
          </a>
          <a
            href="/history"
            style={{
              flex: 1, display: "flex", alignItems: "center", justifyContent: "center",
              borderRadius: "var(--r-md)", padding: "13px",
              background: "var(--surface)", border: "1px solid var(--border)",
              color: "var(--text-muted)", fontWeight: 600, fontSize: 14,
              textDecoration: "none",
            }}
          >
            Histórico
          </a>
        </div>
      </div>
    </div>
  );
}

const MODALITY_LABELS: Record<string, string> = {
  musculacao: "Musculação",
  funcional: "Funcional",
  corrida: "Corrida",
  bike: "Bicicleta",
  caminhada: "Caminhada",
  hiit: "HIIT",
  timed: "Isométrico",
};

function fmtSecs(s: number): string {
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return m > 0 ? `${m}min ${sec.toString().padStart(2, "0")}s` : `${sec}s`;
}

function FatigueCard({ avg, trend, deload }: { avg: number; trend: number | null; deload: boolean }) {
  const isHigh = avg >= 3.5;
  const color = deload ? "var(--hot, #ef4444)" : isHigh ? "#fb923c" : "var(--good, #4ade80)";
  const bg = deload ? "rgba(239,68,68,.08)" : isHigh ? "rgba(251,146,60,.08)" : "rgba(74,222,128,.08)";
  const icon = deload ? "⚠️" : isHigh ? "😓" : "✅";
  const label = deload
    ? `Fadiga elevada (${avg}/5) — considere uma semana de deload`
    : isHigh
    ? `Fadiga moderada (${avg}/5) — descanse bem entre as sessões`
    : `Recuperação boa (${avg}/5) — continue assim`;

  return (
    <div style={{ borderRadius: "var(--r-lg)", background: bg, border: `1px solid ${color}30`, padding: "14px 16px" }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, flex: 1 }}>
          <span style={{ fontSize: 18 }}>{icon}</span>
          <p style={{ fontSize: 13, color: "var(--text)", margin: 0, lineHeight: 1.4 }}>{label}</p>
        </div>
        {trend !== null && Math.abs(trend) >= 5 && (
          <span style={{
            fontSize: 12, fontWeight: 700, color,
            background: `${color}18`, borderRadius: "var(--r-sm)", padding: "3px 8px", flexShrink: 0,
          }}>
            {trend > 0 ? "↑" : "↓"}{Math.abs(trend)}%
          </span>
        )}
      </div>
    </div>
  );
}

function daysAgo(iso: string): string {
  const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000);
  if (diff === 0) return "hoje";
  if (diff === 1) return "ontem";
  return `há ${diff} dias`;
}

function PersonalRecordsBlock({ records }: { records: PersonalRecord[] }) {
  return (
    <div style={{ borderRadius: "var(--r-lg)", background: "var(--surface)", border: "1px solid var(--border)", padding: "16px" }}>
      <p style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.08em", color: "var(--text-dim)", textTransform: "uppercase", marginBottom: 12 }}>
        🏆 Recordes pessoais
      </p>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        {records.map((pr) => (
          <div key={pr.exercise_id} style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <p style={{ fontSize: 13, fontWeight: 600, margin: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {pr.exercise_name}
              </p>
              <p style={{ fontSize: 11, color: "var(--text-dim)", margin: "2px 0 0" }}>{daysAgo(pr.achieved_at)}</p>
            </div>
            <span style={{
              fontSize: 15, fontWeight: 700, color: "var(--primary)",
              background: "var(--primary-soft)", borderRadius: "var(--r-sm)",
              padding: "4px 10px", flexShrink: 0, marginLeft: 12,
            }}>
              {pr.max_weight_kg} kg
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function ModalityMetricsCard({ modality, stats }: { modality: string; stats: Record<string, number | null> }) {
  if (!stats || stats.sessions_count === 0) return null;

  const label = MODALITY_LABELS[modality] ?? modality;
  const items: { label: string; value: string }[] = [];

  if (modality === "timed") {
    if (stats.max_hold_seconds) items.push({ label: "Maior tempo", value: fmtSecs(stats.max_hold_seconds as number) });
    if (stats.avg_hold_seconds) items.push({ label: "Média", value: fmtSecs(stats.avg_hold_seconds as number) });
  } else if (["corrida", "bike", "caminhada"].includes(modality)) {
    if (stats.total_distance_km) items.push({ label: "Distância", value: `${stats.total_distance_km} km` });
    if (stats.total_duration_minutes) items.push({ label: "Tempo", value: `${stats.total_duration_minutes} min` });
    if (stats.avg_speed_kmh) items.push({ label: "Velocidade média", value: `${stats.avg_speed_kmh} km/h` });
  } else if (modality === "hiit") {
    if (stats.total_duration_minutes) items.push({ label: "Tempo total", value: `${stats.total_duration_minutes} min` });
  } else {
    if (stats.total_volume_kg) items.push({ label: "Volume total", value: `${stats.total_volume_kg} kg` });
  }
  items.push({ label: "Sessões (30 dias)", value: String(stats.sessions_count ?? 0) });

  if (items.length === 0) return null;

  return (
    <div style={{ borderRadius: "var(--r-lg)", background: "var(--surface)", border: "1px solid var(--border)", padding: "16px" }}>
      <p style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.08em", color: "var(--text-dim)", textTransform: "uppercase", marginBottom: 12 }}>
        {label} — últimos 30 dias
      </p>
      <div style={{ display: "grid", gridTemplateColumns: `repeat(${Math.min(items.length, 3)}, 1fr)`, gap: 10 }}>
        {items.map((item) => (
          <div key={item.label} style={{ textAlign: "center" }}>
            <p style={{ fontSize: 18, fontWeight: 700, color: "var(--primary)", margin: 0 }}>{item.value}</p>
            <p style={{ fontSize: 11, color: "var(--text-dim)", margin: "2px 0 0" }}>{item.label}</p>
          </div>
        ))}
      </div>
    </div>
  );
}

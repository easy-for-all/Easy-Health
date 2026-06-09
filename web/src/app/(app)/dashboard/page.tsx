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

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const DAYS_PT = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"];

function getTodayLabel(): string {
  const d = new Date();
  return DAYS_PT[d.getDay()]?.toUpperCase() ?? "HOJE";
}

function estimateMinutes(exerciseCount: number): number {
  return Math.round((exerciseCount * 4 + 10) / 5) * 5;
}

export default function DashboardPage() {
  const { user } = useAuth();
  const router = useRouter();
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [streak, setStreak] = useState(0);
  const [weeklySessions, setWeeklySessions] = useState(0);
  const [weeklyGoal, setWeeklyGoal] = useState(3);
  const [aiInsight, setAiInsight] = useState<string | null>(null);
  const [todaySession, setTodaySession] = useState<WorkoutSession | null>(null);
  const [loading, setLoading] = useState(true);
  const [noProfile, setNoProfile] = useState(false);

  useEffect(() => {
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "home" });
  }, []);

  useEffect(() => {
    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<{ streak: number; total_sessions: number; weekly_sessions: number; weekly_goal: number }>(
        "/api/v1/workout_sessions/stats"
      ).catch(() => null),
      api.get<{ suggestion: string; reason: string }>("/api/v1/ai_agents/personal_trainer").catch(() => null),
      api.get<WorkoutSession | Record<string, never>>("/api/v1/workout_sessions/today").catch(() => null),
    ]).then(([p, s, ai, todayRaw]) => {
      if (!p) setNoProfile(true);
      setPlan(p);
      setStreak(s?.streak ?? 0);
      setWeeklySessions(s?.weekly_sessions ?? 0);
      setWeeklyGoal(s?.weekly_goal ?? 3);
      if (ai?.suggestion) {
        setAiInsight(`${ai.suggestion}${ai.reason ? ` <b>—</b> ${ai.reason}` : ""}`);
      }
      if (todayRaw && "id" in todayRaw) {
        setTodaySession(todayRaw as WorkoutSession);
      }
    }).finally(() => setLoading(false));
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
            workoutName={todayDay?.name ?? "Treinar agora"}
            workoutSub={todayDay ? undefined : `${plan?.days?.length ?? 0} treinos no plano`}
            exerciseCount={todayDay?.exercise_count}
            estimatedMin={todayDay?.exercise_count ? estimateMinutes(todayDay.exercise_count) : undefined}
            href={todayDay ? `/workout/today?day=${todayDay.id}` : "/workout/today"}
          />
        )}

        {/* AI Insight */}
        {aiInsight && <InsightCard text={aiInsight} />}

        {/* Streak */}
        <StreakCard
          streak={streak}
          weeklySessions={weeklySessions}
          weeklyGoal={weeklyGoal}
        />

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
                  name={day.name}
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

"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { motion } from "framer-motion";
import { useAuth } from "@/features/auth/auth-context";
import { useTheme } from "@/features/theme/theme-context";
import { api } from "@/shared/lib/api";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { AITrainerCard } from "@/shared/components/ai-trainer";
import type { WorkoutPlan, WorkoutDay } from "@/shared/types/workout";

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

export default function DashboardPage() {
  const { user } = useAuth();
  const { theme, toggleTheme } = useTheme();
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [streak, setStreak] = useState(0);
  const [weeklySessions, setWeeklySessions] = useState(0);
  const [weeklyGoal, setWeeklyGoal] = useState(3);
  const [loading, setLoading] = useState(true);
  const [noProfile, setNoProfile] = useState(false);

  useEffect(() => {
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "home" });
  }, []);

  useEffect(() => {
    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<{ streak: number; total_sessions: number; weekly_sessions: number; weekly_goal: number }>("/api/v1/workout_sessions/stats").catch(() => null),
    ]).then(([p, s]) => {
      if (!p) { setNoProfile(true); }
      setPlan(p);
      setStreak(s?.streak ?? 0);
      setWeeklySessions(s?.weekly_sessions ?? 0);
      setWeeklyGoal(s?.weekly_goal ?? 3);
    }).finally(() => setLoading(false));
  }, []);

  if (loading) return <LoadingScreen />;

  if (noProfile) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center px-4">
        <p className="mb-4 text-center text-gray-600">Complete seu perfil para ver seu plano.</p>
        <Link href="/onboarding" className="rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-white hover:bg-primary-600">
          Completar perfil
        </Link>
      </div>
    );
  }

  return (
    <div className="min-h-screen px-4 py-6">
      <header className="mb-6 flex items-center justify-between">
        <div>
          <p className="text-sm text-gray-500 dark:text-gray-400">Olá,</p>
          <h1 className="text-xl font-bold text-gray-900 dark:text-gray-50">{user?.name}</h1>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={toggleTheme}
            aria-label="Alternar modo escuro"
            className="flex h-8 w-8 items-center justify-center rounded-full border border-gray-200 bg-white text-sm text-gray-500 hover:bg-gray-50 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-400 dark:hover:bg-gray-700"
          >
            {theme === "dark" ? "☀️" : "🌙"}
          </button>
        </div>
      </header>

      <WorkoutCard plan={plan} />

      <StreakCard streak={streak} weeklySessions={weeklySessions} weeklyGoal={weeklyGoal} />

      <section className="mt-4 rounded-2xl border border-gray-100 bg-white p-4 dark:border-gray-800 dark:bg-gray-900" style={{ boxShadow: "var(--shadow-card)" }}>
        <AITrainerCard />
      </section>

      <section className="mt-6">
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">Seus treinos</h2>
        {plan?.days?.length ? (
          <div className="space-y-3">
            {plan.days.map((day, idx) => (
              <DayCard key={day.id} day={day} index={idx} />
            ))}
          </div>
        ) : (
          <div className="rounded-xl border border-dashed border-gray-200 p-6 text-center dark:border-gray-700">
            <p className="mb-3 text-sm text-gray-500 dark:text-gray-400">Nenhum treino cadastrado ainda.</p>
            <Link href="/plan" className="rounded-lg bg-primary-500 px-5 py-2 text-sm font-semibold text-white hover:bg-primary-600">
              Criar plano de treinamento
            </Link>
          </div>
        )}
      </section>

      <div className="mt-4 flex gap-3">
        <Link
          href="/workout/quick"
          className="flex flex-1 items-center justify-center gap-2 rounded-xl bg-primary-50 py-3 text-sm font-semibold text-primary-600 hover:bg-primary-100 dark:bg-primary-950 dark:text-primary-400 dark:hover:bg-primary-900"
        >
          ⚡ Treino Rápido
        </Link>
        <Link
          href="/history"
          className="flex flex-1 items-center justify-center rounded-xl border border-gray-200 py-3 text-sm font-medium text-gray-600 hover:bg-gray-50 dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-800"
        >
          Histórico
        </Link>
      </div>
    </div>
  );
}

function StreakCard({ streak, weeklySessions, weeklyGoal }: { streak: number; weeklySessions: number; weeklyGoal: number }) {
  const progress = Math.min(weeklySessions / Math.max(weeklyGoal, 1), 1);
  const remaining = Math.max(weeklyGoal - weeklySessions, 0);
  const weekDays = ["S", "T", "Q", "Q", "S", "S", "D"];

  return (
    <div className="mt-4 rounded-2xl border border-gray-100 bg-white p-4 dark:border-gray-800 dark:bg-gray-900" style={{ boxShadow: "var(--shadow-card)" }}>
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <motion.span
            animate={streak > 0 ? { scale: [1, 1.15, 1] } : {}}
            transition={{ duration: 1.2, repeat: Infinity, ease: "easeInOut" }}
            className="text-2xl"
          >
            🔥
          </motion.span>
          <div>
            <p className="text-sm font-bold text-gray-900 dark:text-gray-50">
              {streak > 0 ? `${streak} dias seguidos` : "Comece sua ofensiva"}
            </p>
            <p className="text-xs text-gray-400">
              {remaining === 0 ? "Meta semanal atingida! 🎉" : `Faltam ${remaining} treinos para sua meta`}
            </p>
          </div>
        </div>
        <div className="text-right">
          <p className="text-lg font-bold text-primary-500">{weeklySessions}<span className="text-sm text-gray-400">/{weeklyGoal}</span></p>
          <p className="text-xs text-gray-400">esta semana</p>
        </div>
      </div>

      {/* Weekly dots */}
      <div className="mt-3 flex gap-1.5">
        {weekDays.map((day, idx) => (
          <div key={idx} className="flex flex-1 flex-col items-center gap-1">
            <motion.div
              className={`h-2 w-2 rounded-full ${idx < weeklySessions ? "bg-primary-500" : "bg-gray-200 dark:bg-gray-700"}`}
              initial={false}
              animate={idx < weeklySessions ? { scale: [1, 1.3, 1] } : {}}
              transition={{ duration: 0.3, delay: idx * 0.05 }}
            />
            <span className="text-[9px] text-gray-400">{day}</span>
          </div>
        ))}
      </div>

      {/* Progress bar */}
      <div className="mt-3 h-1.5 rounded-full bg-gray-100 dark:bg-gray-800">
        <motion.div
          className="h-1.5 rounded-full bg-primary-500"
          initial={{ width: 0 }}
          animate={{ width: `${progress * 100}%` }}
          transition={{ duration: 0.8, ease: "easeOut", delay: 0.2 }}
        />
      </div>
    </div>
  );
}

function WorkoutCard({ plan }: { plan: WorkoutPlan | null }) {
  const today = new Date().toLocaleDateString("pt-BR", { weekday: "long" });
  return (
    <Link href="/workout/today">
      <div className="rounded-2xl bg-gradient-to-br from-primary-500 to-primary-700 p-5 text-white shadow-md">
        <p className="text-xs font-semibold uppercase tracking-wide text-primary-200">{today}</p>
        <p className="mt-1 text-2xl font-bold">Treinar agora</p>
        <p className="mt-1 text-sm text-primary-100">{plan?.days?.length ?? 0} treinos no seu plano</p>
        <div className="mt-4 inline-flex items-center gap-2 rounded-full bg-white px-4 py-2 text-sm font-semibold text-primary-600">
          Escolher treino <span aria-hidden>→</span>
        </div>
      </div>
    </Link>
  );
}

const MUSCLE_COLORS: Record<string, string> = {
  chest: "bg-red-100 text-red-700",
  back: "bg-blue-100 text-blue-700",
  shoulders: "bg-purple-100 text-purple-700",
  biceps: "bg-yellow-100 text-yellow-700",
  triceps: "bg-orange-100 text-orange-700",
  legs: "bg-green-100 text-green-700",
  core: "bg-teal-100 text-teal-700",
};

function DayCard({ day, index }: { day: WorkoutDay; index: number }) {
  const muscles = day.muscle_groups?.slice(0, 2) ?? [];
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.25, delay: index * 0.06 }}
      className="rounded-xl border border-gray-100 bg-white p-4 dark:border-gray-800 dark:bg-gray-900"
      style={{ boxShadow: "var(--shadow-card)" }}
    >
      <div className="flex items-center justify-between">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary-100 text-xs font-bold text-primary-600 dark:bg-primary-900 dark:text-primary-400">
              {LETTERS[index] ?? index + 1}
            </span>
            <p className="font-semibold text-gray-900 truncate dark:text-gray-50">{day.name}</p>
          </div>
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-xs text-gray-400 dark:text-gray-500">{day.exercise_count} exercícios</span>
            {muscles.map((m) => (
              <span key={m} className={`rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[m] ?? "bg-gray-100 text-gray-600"}`}>
                {m}
              </span>
            ))}
          </div>
        </div>
        <Link href={`/workout/today?day=${day.id}`}>
          <motion.span
            whileTap={{ scale: 0.95 }}
            className="ml-3 block rounded-full bg-primary-500 px-3 py-1.5 text-xs font-semibold text-white whitespace-nowrap hover:bg-primary-600"
          >
            Treinar
          </motion.span>
        </Link>
      </div>
    </motion.div>
  );
}

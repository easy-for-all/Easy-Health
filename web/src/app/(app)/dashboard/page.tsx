"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/features/auth/auth-context";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { AiRecommendationsCard } from "@/shared/components/ai-recommendations-card";
import type { WorkoutPlan, WorkoutDay } from "@/shared/types/workout";

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

export default function DashboardPage() {
  const { user } = useAuth();
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [streak, setStreak] = useState(0);
  const [loading, setLoading] = useState(true);
  const [noProfile, setNoProfile] = useState(false);

  useEffect(() => {
    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<{ streak: number; total_sessions: number }>("/api/v1/workout_sessions/stats").catch(() => null),
    ]).then(([p, s]) => {
      if (!p) { setNoProfile(true); }
      setPlan(p);
      setStreak(s?.streak ?? 0);
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
          <p className="text-sm text-gray-500">Olá,</p>
          <h1 className="text-xl font-bold text-gray-900">{user?.name}</h1>
        </div>
        {streak > 0 && (
          <span className="rounded-full bg-orange-100 px-3 py-1 text-sm font-semibold text-orange-600">
            🔥 {streak} dias
          </span>
        )}
      </header>

      <WorkoutCard plan={plan} />

      <section className="mt-6">
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-500">Seus treinos</h2>
        {plan?.days?.length ? (
          <div className="space-y-3">
            {plan.days.map((day, idx) => (
              <DayCard key={day.id} day={day} index={idx} />
            ))}
          </div>
        ) : (
          <div className="rounded-xl border border-dashed border-gray-200 p-6 text-center">
            <p className="mb-3 text-sm text-gray-500">Nenhum treino cadastrado ainda.</p>
            <Link href="/plan" className="rounded-lg bg-primary-500 px-5 py-2 text-sm font-semibold text-white hover:bg-primary-600">
              Criar plano de treinamento
            </Link>
          </div>
        )}
      </section>

      <section className="mt-6">
        <AiRecommendationsCard />
      </section>

      <div className="mt-4 flex gap-3">
        <Link href="/history" className="flex-1 rounded-lg border border-gray-200 py-3 text-center text-sm font-medium text-gray-600 hover:bg-gray-50">
          Histórico
        </Link>
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
    <div className="rounded-xl border border-gray-100 bg-white p-4 shadow-sm">
      <div className="flex items-center justify-between">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary-100 text-xs font-bold text-primary-600">
              {LETTERS[index] ?? index + 1}
            </span>
            <p className="font-semibold text-gray-900 truncate">{day.name}</p>
          </div>
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-xs text-gray-400">{day.exercise_count} exercícios</span>
            {muscles.map((m) => (
              <span key={m} className={`rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[m] ?? "bg-gray-100 text-gray-600"}`}>
                {m}
              </span>
            ))}
          </div>
        </div>
        <Link href={`/workout/today?day=${day.id}`} className="ml-3 rounded-full bg-primary-500 px-3 py-1.5 text-xs font-semibold text-white whitespace-nowrap">
          Treinar
        </Link>
      </div>
    </div>
  );
}

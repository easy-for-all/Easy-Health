"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { api } from "@/shared/lib/api";
import type { SharedWorkoutPublic } from "@/shared/types/user";

const MUSCLE_GROUPS: Record<string, string> = {
  chest: "Peito", back: "Costas", shoulders: "Ombros",
  biceps: "Bíceps", triceps: "Tríceps", legs: "Pernas", core: "Core",
};

export default function SharedWorkoutPage() {
  const params = useParams();
  const t = useTranslations("sharedWorkouts");
  const [data, setData] = useState<SharedWorkoutPublic | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    api.get<{ shared_workout: SharedWorkoutPublic }>(`/api/v1/s/${params.token}`)
      .then((res) => setData(res.shared_workout))
      .catch(() => setNotFound(true))
      .finally(() => setLoading(false));
  }, [params.token]);

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-50 dark:bg-gray-950">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-primary-500 border-t-transparent" />
      </div>
    );
  }

  if (notFound || !data) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 px-4 bg-gray-50 dark:bg-gray-950">
        <p className="text-2xl">🔒</p>
        <h1 className="text-lg font-semibold text-gray-900 dark:text-gray-100">Treino não encontrado</h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 text-center">
          Este link pode ter expirado ou sido revogado.
        </p>
        <a href="/" className="mt-2 rounded-xl bg-primary-500 px-5 py-2.5 text-sm font-medium text-white">
          Conhecer a EasyHealth
        </a>
      </div>
    );
  }

  const { snapshot } = data;

  return (
    <div className="min-h-screen bg-gray-50 pb-12 dark:bg-gray-950">
      {/* Header */}
      <div className="bg-gradient-to-b from-primary-600 to-primary-500 px-4 pt-12 pb-8 text-white">
        <p className="mb-1 text-sm font-medium opacity-80">{t("shared_by")} {data.shared_by}</p>
        <h1 className="text-2xl font-bold">{data.title}</h1>
        <p className="mt-1 text-sm opacity-75">
          {t("exercises", { count: snapshot.exercise_count })} · {t("views", { count: data.view_count })} visualizações
        </p>
      </div>

      {/* Exercises */}
      <div className="mx-auto max-w-lg space-y-3 px-4 py-6">
        {snapshot.exercises.map((ex, i) => (
          <div key={i} className="rounded-2xl bg-white p-4 shadow-sm dark:bg-gray-900">
            <div className="flex items-start justify-between">
              <div>
                <p className="font-semibold text-gray-900 dark:text-gray-100">{ex.name}</p>
                <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                  {MUSCLE_GROUPS[ex.muscle_group] ?? ex.muscle_group}
                </p>
              </div>
              <div className="text-right text-sm text-gray-700 dark:text-gray-300">
                {ex.sets && ex.reps && (
                  <span className="font-medium">{ex.sets}×{ex.reps}</span>
                )}
                {ex.duration_minutes && (
                  <span className="font-medium">{ex.duration_minutes} min</span>
                )}
              </div>
            </div>
            {ex.rest_seconds && (
              <p className="mt-2 text-xs text-gray-400">Descanso: {ex.rest_seconds}s</p>
            )}
          </div>
        ))}
      </div>

      {/* CTA */}
      <div className="mx-auto max-w-lg px-4">
        <div className="rounded-2xl bg-primary-50 p-5 text-center dark:bg-primary-900/20">
          <p className="mb-3 text-sm font-medium text-primary-800 dark:text-primary-300">
            Quer treinar com seu plano personalizado?
          </p>
          <a
            href="/sign-up"
            className="inline-block rounded-xl bg-primary-500 px-6 py-3 text-sm font-semibold text-white transition-colors hover:bg-primary-600"
          >
            Criar conta grátis na EasyHealth
          </a>
        </div>
      </div>
    </div>
  );
}

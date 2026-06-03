"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { api } from "@/shared/lib/api";
import type { SharedWorkout } from "@/shared/types/user";

const FRONTEND_URL = process.env.NEXT_PUBLIC_FRONTEND_URL ?? "http://localhost:3000";

export default function SharedWorkoutsPage() {
  const router = useRouter();
  const t = useTranslations("sharedWorkouts");
  const [workouts, setWorkouts] = useState<SharedWorkout[]>([]);
  const [loading, setLoading] = useState(true);
  const [copiedId, setCopiedId] = useState<number | null>(null);

  useEffect(() => {
    api.get<{ shared_workouts: SharedWorkout[] }>("/api/v1/shared_workouts")
      .then((data) => setWorkouts(data.shared_workouts))
      .finally(() => setLoading(false));
  }, []);

  async function handleRevoke(id: number) {
    await api.delete(`/api/v1/shared_workouts/${id}`);
    setWorkouts((prev) => prev.filter((w) => w.id !== id));
  }

  function copyLink(sw: SharedWorkout) {
    const url = `${FRONTEND_URL}${sw.share_url}`;
    navigator.clipboard.writeText(url);
    setCopiedId(sw.id);
    setTimeout(() => setCopiedId(null), 2000);
  }

  const visibilityLabel: Record<string, string> = {
    private_link: t("private_link"),
    specific_users: t("specific_users"),
    community: t("community"),
  };

  return (
    <div className="min-h-screen bg-gray-50 pb-24 dark:bg-gray-950">
      <header className="sticky top-0 z-10 flex items-center gap-3 border-b border-gray-100 bg-white/90 px-4 py-4 backdrop-blur-sm dark:border-gray-800 dark:bg-gray-950/90">
        <button onClick={() => router.back()} className="text-gray-500 dark:text-gray-400">←</button>
        <h1 className="text-base font-semibold text-gray-900 dark:text-gray-100">{t("title")}</h1>
      </header>

      <div className="mx-auto max-w-lg space-y-3 px-4 py-4">
        {loading && (
          <div className="py-12 text-center text-sm text-gray-400">Carregando...</div>
        )}

        {!loading && workouts.length === 0 && (
          <div className="py-12 text-center">
            <p className="text-sm text-gray-500 dark:text-gray-400">{t("no_shared")}</p>
          </div>
        )}

        {workouts.map((sw) => (
          <div key={sw.id} className="rounded-2xl bg-white p-4 shadow-sm dark:bg-gray-900">
            <div className="mb-3 flex items-start justify-between">
              <div>
                <p className="font-medium text-gray-900 dark:text-gray-100">{sw.title}</p>
                <div className="mt-1 flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                  <span className="rounded-full bg-gray-100 px-2 py-0.5 dark:bg-gray-800">{visibilityLabel[sw.visibility]}</span>
                  <span>{t("exercises", { count: sw.exercise_count })}</span>
                  <span>{t("views", { count: sw.view_count })}</span>
                </div>
              </div>
            </div>

            <div className="flex gap-2">
              <button
                onClick={() => copyLink(sw)}
                className="flex-1 rounded-lg bg-primary-50 px-3 py-2 text-xs font-medium text-primary-700 transition-colors hover:bg-primary-100 dark:bg-primary-900/30 dark:text-primary-300"
              >
                {copiedId === sw.id ? t("copied") : t("copy_link")}
              </button>
              <button
                onClick={() => handleRevoke(sw.id)}
                className="rounded-lg bg-red-50 px-3 py-2 text-xs font-medium text-red-600 transition-colors hover:bg-red-100 dark:bg-red-900/30 dark:text-red-400"
              >
                {t("revoke")}
              </button>
            </div>

            {sw.expires_at && (
              <p className="mt-2 text-xs text-amber-600 dark:text-amber-400">
                Expira em {new Date(sw.expires_at).toLocaleDateString()}
              </p>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

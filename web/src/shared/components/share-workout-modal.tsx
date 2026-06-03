"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { api } from "@/shared/lib/api";
import type { SharedWorkout } from "@/shared/types/user";

interface ShareWorkoutModalProps {
  workoutDayId: number;
  workoutDayName: string;
  onClose: () => void;
  onShared: (shared: SharedWorkout) => void;
}

export function ShareWorkoutModal({ workoutDayId, workoutDayName, onClose, onShared }: ShareWorkoutModalProps) {
  const t = useTranslations("sharedWorkouts");
  const [title, setTitle] = useState(workoutDayName);
  const [visibility, setVisibility] = useState<"private_link" | "specific_users" | "community">("private_link");
  const [includeWeights, setIncludeWeights] = useState(false);
  const [expiresInDays, setExpiresInDays] = useState<string>("");
  const [loading, setLoading] = useState(false);

  async function handleShare() {
    setLoading(true);
    try {
      const payload: Record<string, unknown> = {
        workout_day_id: workoutDayId,
        title,
        visibility,
        include_weights: includeWeights,
      };
      if (expiresInDays) payload.expires_in_days = parseInt(expiresInDays);

      const data = await api.post<{ shared_workout: SharedWorkout }>(
        `/api/v1/workout_days/${workoutDayId}/share`,
        payload
      );
      onShared(data.shared_workout);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 sm:items-center">
      <div className="w-full max-w-md rounded-t-2xl bg-white p-6 shadow-xl dark:bg-gray-900 sm:rounded-2xl">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">{t("share")}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300">✕</button>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">{t("share_title")}</label>
            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">{t("visibility")}</label>
            <select
              value={visibility}
              onChange={(e) => setVisibility(e.target.value as typeof visibility)}
              className="w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100"
            >
              <option value="private_link">{t("private_link")}</option>
              <option value="community">{t("community")}</option>
            </select>
          </div>

          <label className="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={includeWeights}
              onChange={(e) => setIncludeWeights(e.target.checked)}
              className="h-4 w-4 rounded border-gray-300 text-primary-500"
            />
            <span className="text-sm text-gray-700 dark:text-gray-300">{t("include_weights")}</span>
          </label>

          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">{t("expires_in")}</label>
            <select
              value={expiresInDays}
              onChange={(e) => setExpiresInDays(e.target.value)}
              className="w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100"
            >
              <option value="">{t("no_expiry")}</option>
              <option value="7">{t("7_days")}</option>
              <option value="30">{t("30_days")}</option>
            </select>
          </div>
        </div>

        <div className="mt-6 flex gap-3">
          <button
            onClick={onClose}
            className="flex-1 rounded-lg border border-gray-200 py-2.5 text-sm font-medium text-gray-700 dark:border-gray-700 dark:text-gray-300"
          >
            Cancelar
          </button>
          <button
            onClick={handleShare}
            disabled={loading || !title.trim()}
            className="flex-1 rounded-lg bg-primary-500 py-2.5 text-sm font-medium text-white disabled:opacity-50"
          >
            {loading ? "..." : t("share")}
          </button>
        </div>
      </div>
    </div>
  );
}

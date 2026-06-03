"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { api } from "@/shared/lib/api";
import { PrivacyToggle } from "@/shared/components/privacy-toggle";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { ClientPermissions } from "@/shared/types/personal";

const PERMISSION_KEYS: (keyof ClientPermissions)[] = [
  "can_view_assigned_workouts",
  "can_view_completed_workouts",
  "can_view_adherence",
  "can_view_exercise_performance",
  "can_view_body_weight",
  "can_view_photos",
  "can_view_body_analysis",
];

export default function ClientPermissionsPage() {
  const t = useTranslations("clientPermissions");
  const router = useRouter();
  const [personalName, setPersonalName] = useState<string | null>(null);
  const [permissions, setPermissions] = useState<ClientPermissions | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [savedMsg, setSavedMsg] = useState("");
  const [noTrainer, setNoTrainer] = useState(false);

  useEffect(() => {
    api.get<{ personal_name: string; permissions: ClientPermissions }>("/api/v1/client_permissions")
      .then((data) => {
        setPersonalName(data.personal_name);
        setPermissions(data.permissions);
      })
      .catch(() => setNoTrainer(true))
      .finally(() => setLoading(false));
  }, []);

  async function handleToggle(key: keyof ClientPermissions, value: boolean) {
    if (!permissions) return;
    const updated = { ...permissions, [key]: value };
    setPermissions(updated);
    setSaving(true);
    try {
      await api.patch("/api/v1/client_permissions", { [key]: value });
      setSavedMsg(t("saved"));
      setTimeout(() => setSavedMsg(""), 2000);
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <LoadingScreen />;

  if (noTrainer || !permissions) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 px-4">
        <p className="text-center text-sm text-gray-500 dark:text-gray-400">{t("no_trainer")}</p>
        <button onClick={() => router.back()} className="text-primary-500 text-sm">← Voltar</button>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 pb-24 dark:bg-gray-950">
      <header className="sticky top-0 z-10 flex items-center gap-3 border-b border-gray-100 bg-white/90 px-4 py-4 backdrop-blur-sm dark:border-gray-800 dark:bg-gray-950/90">
        <button onClick={() => router.back()} className="text-gray-500 dark:text-gray-400">←</button>
        <div className="flex-1">
          <h1 className="text-base font-semibold text-gray-900 dark:text-gray-100">{t("title")}</h1>
          {personalName && <p className="text-xs text-gray-500 dark:text-gray-400">{personalName}</p>}
        </div>
        {savedMsg && <span className="text-xs text-green-600 dark:text-green-400">{savedMsg}</span>}
      </header>

      <div className="mx-auto max-w-lg px-4 py-6 space-y-4">
        <p className="text-sm text-gray-600 dark:text-gray-400">{t("subtitle")}</p>

        <div className="rounded-2xl bg-white p-5 shadow-sm dark:bg-gray-900">
          <div className="divide-y divide-gray-100 dark:divide-gray-800">
            {PERMISSION_KEYS.map((key) => (
              <PrivacyToggle
                key={key}
                checked={permissions[key]}
                onChange={(v) => handleToggle(key, v)}
                label={t(key as keyof typeof t)}
                disabled={saving}
              />
            ))}
            {/* Exams: always disabled in MVP */}
            <PrivacyToggle
              checked={false}
              onChange={() => {}}
              label={t("can_view_exams")}
              disabled
            />
          </div>
        </div>
      </div>
    </div>
  );
}

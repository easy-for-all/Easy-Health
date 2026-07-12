"use client";

import { useEffect, useState } from "react";
import { PrivacyToggle } from "@/shared/components/privacy-toggle";
import { trackEvent } from "@/shared/lib/analytics";
import { getPushPermissionState, type PushPermissionState } from "@/shared/lib/pushNotifications";
import { useNotificationSettings } from "./use-notification-settings";

const PERIODS: { value: string; label: string }[] = [
  { value: "morning", label: "De manhã" },
  { value: "lunch", label: "No horário do almoço" },
  { value: "afternoon", label: "À tarde" },
  { value: "evening", label: "À noite" },
  { value: "variable", label: "Meu horário varia" },
];

const TIME_OPTIONS: string[] = Array.from({ length: (22 - 5) * 2 + 1 }, (_, i) => {
  const minutes = 5 * 60 + i * 30;
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
});

export function NotificationSettingsSection() {
  const { settings, loading, update } = useNotificationSettings();
  const [saving, setSaving] = useState(false);
  const [permission, setPermission] = useState<PushPermissionState>("unsupported");

  useEffect(() => {
    getPushPermissionState().then(setPermission).catch(() => setPermission("unsupported"));
  }, []);

  if (loading || !settings) return null;

  async function patch(patch: Parameters<typeof update>[0]) {
    setSaving(true);
    try {
      await update(patch);
    } finally {
      setSaving(false);
    }
  }

  const systemBlocked = permission === "denied" || permission === "permanently_denied";
  const isVariable = settings.preferred_workout_period === "variable" || !settings.preferred_workout_period;

  return (
    <section className="rounded-2xl bg-white p-5 shadow-sm dark:bg-gray-900">
      <h2 className="mb-4 text-sm font-semibold uppercase tracking-wide text-gray-700 dark:text-gray-300">
        Notificações
      </h2>

      {systemBlocked && (
        <div className="mb-4 rounded-xl bg-amber-50 p-3 text-xs text-amber-700 dark:bg-amber-950/40 dark:text-amber-300">
          As notificações estão desativadas no Android. Ative-as nas configurações do aparelho para receber os lembretes.
        </div>
      )}

      <div className="divide-y divide-gray-100 dark:divide-gray-800">
        <PrivacyToggle
          checked={settings.workout_reminders_enabled}
          onChange={(v) => {
            if (!v) trackEvent("notification_type_disabled", { platform: "android", reason: "user_settings" });
            patch({ workout_reminders_enabled: v });
          }}
          label="Lembretes de treino"
          description="Lembramos você no horário em que costuma treinar."
        />

        <PrivacyToggle
          checked={settings.workout_ready_enabled}
          onChange={(v) => patch({ workout_ready_enabled: v })}
          label="Avisar quando meu treino estiver pronto"
        />

        {/* Dicas e novidades — preparado, sem envio neste MVP */}
        <PrivacyToggle
          checked={false}
          onChange={() => {}}
          disabled
          label="Dicas e novidades"
          description="Em breve."
        />
      </div>

      <div className="mt-4">
        <label className="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">Horário preferido</label>
        <div className="flex gap-2">
          <select
            className="flex-1 rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100"
            value={settings.preferred_workout_period ?? ""}
            disabled={saving}
            onChange={(e) => {
              const period = e.target.value;
              trackEvent("notification_time_changed", { platform: "android", period });
              patch({ preferred_workout_period: period, preferred_workout_time: period === "variable" ? "" : settings.preferred_workout_time || "19:00" });
            }}
          >
            <option value="">Selecione</option>
            {PERIODS.map((p) => (
              <option key={p.value} value={p.value}>{p.label}</option>
            ))}
          </select>
          {!isVariable && (
            <select
              className="w-28 rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100"
              value={settings.preferred_workout_time ?? ""}
              disabled={saving}
              onChange={(e) => {
                trackEvent("notification_time_changed", { platform: "android" });
                patch({ preferred_workout_time: e.target.value });
              }}
            >
              {TIME_OPTIONS.map((t) => (
                <option key={t} value={t}>{t}</option>
              ))}
            </select>
          )}
        </div>
      </div>

      <p className="mt-4 text-xs text-gray-400 dark:text-gray-500">Você pode mudar isso quando quiser.</p>
    </section>
  );
}

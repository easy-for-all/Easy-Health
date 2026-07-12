"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/shared/lib/api";

export interface NotificationSettings {
  push_enabled: boolean;
  workout_reminders_enabled: boolean;
  workout_ready_enabled: boolean;
  preferred_workout_period: string | null;
  preferred_workout_time: string | null; // "HH:MM"
  timezone: string | null;
  notifications_disabled_at: string | null;
  has_active_device: boolean;
}

export function useNotificationSettings() {
  const [settings, setSettings] = useState<NotificationSettings | null>(null);
  const [loading, setLoading] = useState(true);

  const fetch = useCallback(async () => {
    try {
      const data = await api.get<NotificationSettings>("/api/v1/notification_preferences");
      setSettings(data);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetch();
  }, [fetch]);

  const update = useCallback(async (patch: Partial<NotificationSettings>) => {
    const updated = await api.patch<NotificationSettings>("/api/v1/notification_preferences", patch);
    setSettings(updated);
    return updated;
  }, []);

  return { settings, loading, update, refetch: fetch };
}

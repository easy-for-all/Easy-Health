"use client";

import { useState, useEffect, useCallback } from "react";
import { api } from "@/shared/lib/api";
import type { PrivacySettings, PublicProfileSettings } from "@/shared/types/user";

export function usePrivacySettings() {
  const [settings, setSettings] = useState<PrivacySettings | null>(null);
  const [loading, setLoading] = useState(true);

  const fetch = useCallback(async () => {
    try {
      const data = await api.get<PrivacySettings>("/api/v1/privacy_settings");
      setSettings(data);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetch(); }, [fetch]);

  const update = useCallback(async (patch: Partial<PrivacySettings>) => {
    const updated = await api.patch<PrivacySettings>("/api/v1/privacy_settings", patch);
    setSettings(updated);
    return updated;
  }, []);

  return { settings, loading, update, refetch: fetch };
}

export function usePublicProfile() {
  const [profile, setProfile] = useState<PublicProfileSettings | null>(null);
  const [loading, setLoading] = useState(true);

  const fetch = useCallback(async () => {
    try {
      const data = await api.get<{ public_profile: PublicProfileSettings }>("/api/v1/public_profile");
      setProfile(data.public_profile);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetch(); }, [fetch]);

  const update = useCallback(async (patch: Partial<PublicProfileSettings>) => {
    const data = await api.patch<{ public_profile: PublicProfileSettings }>("/api/v1/public_profile", patch);
    setProfile(data.public_profile);
    return data.public_profile;
  }, []);

  return { profile, loading, update, refetch: fetch };
}

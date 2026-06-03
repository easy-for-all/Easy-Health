"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { usePrivacySettings, usePublicProfile } from "@/features/privacy/use-privacy";
import { useAuth } from "@/features/auth/auth-context";
import { PrivacyToggle } from "@/shared/components/privacy-toggle";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { ProfileVisibility } from "@/shared/types/user";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

export default function SettingsPage() {
  const t = useTranslations("privacy");
  const tPub = useTranslations("publicProfile");
  const router = useRouter();
  const { updateUser } = useAuth();
  const { settings, loading: loadingPrivacy, update: updatePrivacy } = usePrivacySettings();
  const { profile, loading: loadingProfile, update: updateProfile } = usePublicProfile();
  const [saving, setSaving] = useState(false);
  const [savedMsg, setSavedMsg] = useState("");
  const [copied, setCopied] = useState(false);

  if (loadingPrivacy || loadingProfile) return <LoadingScreen />;
  if (!settings || !profile) return null;

  async function handleVisibilityChange(value: ProfileVisibility) {
    setSaving(true);
    try {
      const updated = await updatePrivacy({ profile_visibility: value });
      updateUser({ profile_visibility: updated.profile_visibility });
      showSaved();
    } finally {
      setSaving(false);
    }
  }

  async function handleCommunityToggle(value: boolean) {
    setSaving(true);
    try {
      await updatePrivacy({ community_enabled: value });
      showSaved();
    } finally {
      setSaving(false);
    }
  }

  async function handleProfileToggle(field: string, value: boolean) {
    setSaving(true);
    try {
      await updateProfile({ [field]: value });
      showSaved();
    } finally {
      setSaving(false);
    }
  }

  function showSaved() {
    setSavedMsg(t("saved"));
    setTimeout(() => setSavedMsg(""), 2000);
  }

  function copyReferral() {
    if (!settings) return;
    navigator.clipboard.writeText(settings.referral_code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  const visibilityOptions: { value: ProfileVisibility; label: string; desc: string }[] = [
    { value: "private", label: t("private"), desc: t("private_desc") },
    { value: "public_limited", label: t("public_limited"), desc: t("public_limited_desc") },
    { value: "public", label: t("public"), desc: t("public_desc") },
  ];

  return (
    <div className="min-h-screen bg-gray-50 pb-24 dark:bg-gray-950">
      <header className="sticky top-0 z-10 flex items-center gap-3 border-b border-gray-100 bg-white/90 px-4 py-4 backdrop-blur-sm dark:border-gray-800 dark:bg-gray-950/90">
        <button onClick={() => router.back()} className="text-gray-500 dark:text-gray-400">
          ←
        </button>
        <h1 className="text-base font-semibold text-gray-900 dark:text-gray-100">{t("title")}</h1>
        {savedMsg && (
          <span className="ml-auto text-xs text-green-600 dark:text-green-400">{savedMsg}</span>
        )}
      </header>

      <div className="mx-auto max-w-lg space-y-6 px-4 py-6">
        {/* Visibilidade do perfil */}
        <section className="rounded-2xl bg-white p-5 shadow-sm dark:bg-gray-900">
          <h2 className="mb-4 text-sm font-semibold text-gray-700 dark:text-gray-300 uppercase tracking-wide">{t("visibility")}</h2>
          <div className="space-y-2">
            {visibilityOptions.map(({ value, label, desc }) => (
              <label key={value} className="flex cursor-pointer items-start gap-3 rounded-xl p-3 transition-colors hover:bg-gray-50 dark:hover:bg-gray-800">
                <input
                  type="radio"
                  name="visibility"
                  value={value}
                  checked={settings.profile_visibility === value}
                  onChange={() => handleVisibilityChange(value)}
                  className="mt-0.5 h-4 w-4 text-primary-500"
                />
                <div>
                  <span className="block text-sm font-medium text-gray-900 dark:text-gray-100">{label}</span>
                  <span className="block text-xs text-gray-500 dark:text-gray-400">{desc}</span>
                </div>
              </label>
            ))}
          </div>
        </section>

        {/* Comunidade */}
        <section className="rounded-2xl bg-white p-5 shadow-sm dark:bg-gray-900">
          <div className="divide-y divide-gray-100 dark:divide-gray-800">
            <PrivacyToggle
              checked={settings.community_enabled}
              onChange={handleCommunityToggle}
              label={t("community")}
              description={t("community_desc")}
            />
          </div>
        </section>

        {/* Configurações do perfil público */}
        {settings.profile_visibility !== "private" && (
          <section className="rounded-2xl bg-white p-5 shadow-sm dark:bg-gray-900">
            <h2 className="mb-4 text-sm font-semibold text-gray-700 dark:text-gray-300 uppercase tracking-wide">{tPub("title")}</h2>
            <div className="divide-y divide-gray-100 dark:divide-gray-800">
              <PrivacyToggle
                checked={profile.avatar_visible}
                onChange={(v) => handleProfileToggle("avatar_visible", v)}
                label={tPub("show_avatar")}
              />
              <PrivacyToggle
                checked={profile.show_workout_count}
                onChange={(v) => handleProfileToggle("show_workout_count", v)}
                label={tPub("show_workout_count")}
              />
              <PrivacyToggle
                checked={profile.show_streak}
                onChange={(v) => handleProfileToggle("show_streak", v)}
                label={tPub("show_streak")}
              />
            </div>
          </section>
        )}

        {/* Código de indicação */}
        <section className="rounded-2xl bg-white p-5 shadow-sm dark:bg-gray-900">
          <h2 className="mb-3 text-sm font-semibold text-gray-700 dark:text-gray-300 uppercase tracking-wide">{t("referral_code")}</h2>
          <div className="flex items-center gap-3">
            <span className="flex-1 rounded-lg bg-gray-50 px-4 py-2.5 font-mono text-lg font-bold tracking-widest text-gray-900 dark:bg-gray-800 dark:text-gray-100">
              {settings.referral_code}
            </span>
            <button
              onClick={copyReferral}
              className="rounded-lg bg-primary-500 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-600"
            >
              {copied ? t("referral_copied") : t("referral_copy")}
            </button>
          </div>
        </section>
      </div>
    </div>
  );
}

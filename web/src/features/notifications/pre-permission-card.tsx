"use client";

import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import { trackEvent } from "@/shared/lib/analytics";
import { useToast } from "@/shared/components/ui/toast-provider";
import {
  getPushPermissionState,
  requestPushPermissionAndRegister,
  type PushPermissionState,
} from "@/shared/lib/pushNotifications";

const ANSWERED_KEY = "eh_push_prepermission_answered";

interface NotificationPrefs {
  workout_reminders_enabled: boolean;
  preferred_workout_period: string | null;
  preferred_workout_time: string | null;
}

function answeredLocally(): boolean {
  try {
    return localStorage.getItem(ANSWERED_KEY) === "1";
  } catch {
    return false;
  }
}

function markAnswered(): void {
  try {
    localStorage.setItem(ANSWERED_KEY, "1");
  } catch {
    /* ignore */
  }
}

// Contextual opt-in shown AFTER the workout is ready (never on app boot). Only
// renders on the native platform when permission hasn't been granted yet and the
// user hasn't already answered.
export function PrePermissionCard({ onboardingStage = "workout_ready" }: { onboardingStage?: string }) {
  const toast = useToast();
  const [visible, setVisible] = useState(false);
  const [prefs, setPrefs] = useState<NotificationPrefs | null>(null);
  const [permissionState, setPermissionState] = useState<PushPermissionState>("unsupported");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let active = true;
    (async () => {
      const state = await getPushPermissionState();
      if (!active) return;
      setPermissionState(state);
      if (state === "unsupported" || state === "granted" || answeredLocally()) return;

      const p = await api.get<NotificationPrefs>("/api/v1/notification_preferences").catch(() => null);
      if (!active) return;
      if (p?.workout_reminders_enabled) return; // already opted in
      setPrefs(p);
      setVisible(true);
      trackEvent("push_prepermission_viewed", { platform: "android", source: "workout_ready", onboarding_stage: onboardingStage });
    })();
    return () => {
      active = false;
    };
  }, [onboardingStage]);

  async function handleEnable() {
    setBusy(true);
    trackEvent("push_prepermission_accepted", { platform: "android", onboarding_stage: onboardingStage });
    trackEvent("push_permission_requested", { platform: "android", permission_status: permissionState });
    trackEvent("push_token_registration_started", { platform: "android" });

    const state = await requestPushPermissionAndRegister();
    setPermissionState(state);

    if (state === "granted") {
      trackEvent("push_permission_granted", { platform: "android" });
      try {
        await api.patch("/api/v1/notification_preferences", {
          push_enabled: true,
          workout_reminders_enabled: true,
        });
        trackEvent("push_token_registered", { platform: "android" });
        toast.show("Pronto! Vamos te lembrar no horário certo.", { variant: "good" });
      } catch {
        trackEvent("push_token_registration_failed", { platform: "android" });
      }
      markAnswered();
      setVisible(false);
    } else {
      trackEvent("push_permission_denied", { platform: "android", permission_status: state });
      if (state === "permanently_denied") {
        // Keep the card but switch it to settings guidance.
        setBusy(false);
        return;
      }
      markAnswered();
      setVisible(false);
    }
    setBusy(false);
  }

  function handleDecline() {
    trackEvent("push_prepermission_declined", { platform: "android", onboarding_stage: onboardingStage });
    markAnswered();
    setVisible(false);
  }

  function handleOpenSettings() {
    trackEvent("push_permission_open_settings_clicked", { platform: "android" });
    toast.show("Ative as notificações da EasyHealth nas configurações do Android.", { variant: "default" });
  }

  if (!visible) return null;

  const time = prefs?.preferred_workout_time;
  const isVariable = prefs?.preferred_workout_period === "variable" || !time;

  if (permissionState === "permanently_denied") {
    return (
      <div style={cardStyle}>
        <p style={titleStyle}>Notificações estão desativadas no Android</p>
        <p style={descStyle}>
          Para receber o lembrete do seu treino, ative as notificações da EasyHealth nas configurações do aparelho.
        </p>
        <button style={primaryBtn} onClick={handleOpenSettings}>Como ativar</button>
        <button style={ghostBtn} onClick={handleDecline}>Agora não</button>
      </div>
    );
  }

  return (
    <div style={cardStyle}>
      <p style={titleStyle}>Quer que a EasyHealth lembre você no horário em que costuma treinar?</p>
      <p style={descStyle}>
        Enviaremos no máximo dois lembretes para ajudar você a começar. Você pode desativar quando quiser.
      </p>
      <p style={{ ...descStyle, color: "var(--primary)", fontWeight: 600 }}>
        {isVariable
          ? "Você poderá escolher um horário para receber seu lembrete."
          : `Você disse que costuma treinar por volta das ${time}.`}
      </p>
      <button style={primaryBtn} onClick={handleEnable} disabled={busy}>
        {busy ? "Ativando…" : "Ativar lembretes"}
      </button>
      <button style={ghostBtn} onClick={handleDecline} disabled={busy}>Agora não</button>
    </div>
  );
}

const cardStyle: React.CSSProperties = {
  background: "var(--surface)",
  border: "1px solid var(--border)",
  borderRadius: "var(--r-lg)",
  padding: 18,
  marginBottom: 14,
};
const titleStyle: React.CSSProperties = { fontWeight: 700, fontSize: 15, margin: "0 0 6px" };
const descStyle: React.CSSProperties = { fontSize: 13, color: "var(--text-muted)", margin: "0 0 10px" };
const primaryBtn: React.CSSProperties = {
  width: "100%", borderRadius: "var(--r-pill)", padding: "14px",
  background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
  color: "var(--on-primary)", fontWeight: 700, fontSize: 14, border: 0, cursor: "pointer", marginBottom: 8,
};
const ghostBtn: React.CSSProperties = {
  width: "100%", borderRadius: "var(--r-pill)", padding: "12px",
  background: "transparent", color: "var(--text-muted)", fontWeight: 600, fontSize: 13,
  border: "1px solid var(--border)", cursor: "pointer",
};

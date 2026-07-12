import { api } from "./api";
import { resolveDeepLink } from "./push-deep-link";

// Centralized push service. Responsibilities:
// - never prompt for permission unless explicitly asked (pre-permission opt-in);
// - register + attach listeners exactly once;
// - report the device token to the backend with metadata;
// - route notification taps through a safe deep-link allowlist;
// - no-op on the web (only runs on the native Android platform).

export type PushPermissionState =
  | "granted"
  | "denied"
  | "permanently_denied"
  | "prompt"
  | "unsupported";

const REQUESTED_KEY = "eh_push_requested";
let listenersAttached = false;

async function isNative(): Promise<boolean> {
  try {
    const { Capacitor } = await import("@capacitor/core");
    return Capacitor.isNativePlatform();
  } catch {
    return false;
  }
}

function markRequested(): void {
  try {
    localStorage.setItem(REQUESTED_KEY, "1");
  } catch {
    /* ignore */
  }
}

function wasRequestedBefore(): boolean {
  try {
    return localStorage.getItem(REQUESTED_KEY) === "1";
  } catch {
    return false;
  }
}

function mapState(receive: string): PushPermissionState {
  if (receive === "granted") return "granted";
  // The plugin only reports "denied"; treat a denial after we already asked as
  // permanently denied so the UI stops prompting and explains system settings.
  if (receive === "denied") return wasRequestedBefore() ? "permanently_denied" : "denied";
  return "prompt";
}

export async function getPushPermissionState(): Promise<PushPermissionState> {
  if (!(await isNative())) return "unsupported";
  const { PushNotifications } = await import("@capacitor/push-notifications");
  const status = await PushNotifications.checkPermissions();
  return mapState(status.receive);
}

// Called on login. Only registers if permission was ALREADY granted — it never
// shows the native prompt (that only happens via the pre-permission opt-in).
export async function syncPushIfGranted(): Promise<void> {
  if (!(await isNative())) return;
  if ((await getPushPermissionState()) !== "granted") return;
  await attachListeners();
  await ensureChannel();
  await registerDevice();
}

// Called from the pre-permission card when the user taps "Ativar lembretes".
export async function requestPushPermissionAndRegister(): Promise<PushPermissionState> {
  if (!(await isNative())) return "unsupported";
  const { PushNotifications } = await import("@capacitor/push-notifications");
  markRequested();

  let status = await PushNotifications.checkPermissions();
  if (status.receive === "prompt" || status.receive === "prompt-with-rationale") {
    status = await PushNotifications.requestPermissions();
  }

  const state = mapState(status.receive);
  if (state === "granted") {
    await attachListeners();
    await ensureChannel();
    await registerDevice();
  }
  return state;
}

async function registerDevice(): Promise<void> {
  const { PushNotifications } = await import("@capacitor/push-notifications");
  await PushNotifications.register();
}

async function attachListeners(): Promise<void> {
  if (listenersAttached) return;
  listenersAttached = true;

  const { PushNotifications } = await import("@capacitor/push-notifications");
  await PushNotifications.removeAllListeners();

  await PushNotifications.addListener("registration", ({ value }) => {
    void sendToken(value);
  });
  await PushNotifications.addListener("registrationError", (err) => {
    console.error("[Push] Registration error:", err.error);
  });
  await PushNotifications.addListener("pushNotificationReceived", (notification) => {
    console.log("[Push] Foreground notification:", notification.title);
  });
  await PushNotifications.addListener("pushNotificationActionPerformed", (action) => {
    void handleActionPerformed(action.notification?.data ?? {});
  });
}

async function sendToken(token: string): Promise<void> {
  try {
    await api.post("/api/v1/device_tokens", {
      token,
      platform: "android",
      permission_status: "granted",
      ...(await deviceMetadata()),
    });
  } catch {
    // token registration is best-effort
  }
}

async function deviceMetadata(): Promise<Record<string, string>> {
  const meta: Record<string, string> = {};
  try {
    const { App } = await import("@capacitor/app");
    const info = await App.getInfo();
    meta.app_version = info.version;
  } catch {
    /* @capacitor/app may be unavailable */
  }
  if (typeof navigator !== "undefined" && navigator.userAgent) {
    meta.os_version = navigator.userAgent;
  }
  return meta;
}

async function ensureChannel(): Promise<void> {
  try {
    const { PushNotifications } = await import("@capacitor/push-notifications");
    await PushNotifications.createChannel({
      id: "workout_reminders",
      name: "Lembretes de treino",
      description: "Lembretes para você começar seu treino",
      importance: 4,
      visibility: 1,
    });
  } catch {
    /* channels are Android-only / best-effort */
  }
}

async function handleActionPerformed(data: Record<string, unknown>): Promise<void> {
  const deliveryId = data.delivery_id;
  if (deliveryId != null) {
    try {
      await api.post(`/api/v1/notification_deliveries/${deliveryId}/opened`, {});
    } catch {
      /* attribution is best-effort */
    }
  }
  const path = resolveDeepLink(data);
  // Carry the delivery id so the target screen can offer "não gostei" feedback.
  const target = deliveryId != null ? `${path}${path.includes("?") ? "&" : "?"}from_push=${deliveryId}` : path;
  if (typeof window !== "undefined") window.location.assign(target);
}

import { api, ApiError } from "./api";
import { trackEvent } from "./analytics";
import { resolveDeepLink } from "./push-deep-link";

// Centralized push service. Responsibilities:
// - never prompt for permission unless explicitly asked (pre-permission opt-in);
// - attach permanent listeners exactly once (foreground + tap routing);
// - own a single, awaited, observable token-registration operation with timeout;
// - be the ONLY caller of the backend sync (the "registration" event just hands
//   the token to the pending operation — it never posts);
// - report the device token to the backend with safe metadata (never the token);
// - no-op on the web (only runs on the native Android platform).

export type PushPermissionState =
  | "granted"
  | "denied"
  | "permanently_denied"
  | "prompt"
  | "unsupported";

export type PushRegistrationSource =
  | "auth_boot"
  | "login"
  | "prepermission_card"
  | "permission_granted";

export type PushRegistrationFailureReason =
  | "unsupported"
  | "permission_denied"
  | "registration_error"
  | "registration_timeout"
  | "backend_sync_failed";

export interface PushRegistrationResult {
  permissionState: PushPermissionState;
  // true only when the FCM token was obtained AND persisted by the backend.
  registered: boolean;
  failureReason?: PushRegistrationFailureReason;
}

const REQUESTED_KEY = "eh_push_requested";
const REGISTRATION_TIMEOUT_MS = 15_000;

let permanentListenersAttached = false;
// Only ever one registration operation in flight (dedupe + no cross-op races).
let inFlight: Promise<PushRegistrationResult> | null = null;

// Safe, in-memory diagnostics state for the admin device panel. NEVER stores the
// raw token — only a mask. Reset on reload; this is a live debugging aid, not a
// persisted record.
let lastMaskedToken: string | null = null;
let lastRegistrationAt: string | null = null;
let lastTokenSyncedToApi: boolean | null = null;
let lastApiStatus: number | "ok" | null = null;
let lastForeground: { title: string | null; at: string } | null = null;
let lastAction: { path: string | null; type: string | null; at: string } | null = null;

export interface PushDiagnosticsSnapshot {
  platform: string;
  isNative: boolean;
  permissionState: PushPermissionState;
  maskedToken: string | null;
  tokenSyncedToApi: boolean | null;
  lastApiStatus: number | "ok" | null;
  lastRegistrationAt: string | null;
  channelId: string;
  appVersion: string | null;
  build: string | null;
  firebaseHint: string;
  lastForeground: { title: string | null; at: string } | null;
  lastAction: { path: string | null; type: string | null; at: string } | null;
}

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

// ---------------------------------------------------------------------------
// Safe observability. These events are emitted in production too (via the
// existing analytics pipeline) so we can locate failures on installed builds.
// NEVER include the token (even masked), Authorization, response bodies, or PII.
// ---------------------------------------------------------------------------
type PushEventMeta = {
  source?: PushRegistrationSource;
  app_version?: string;
  os_version?: string;
  permission_status?: PushPermissionState;
  error_category?: string;
  http_status?: number;
};

function trackPushEvent(event: string, meta: PushEventMeta): void {
  trackEvent(event, { platform: "android", ...meta });
}

// The ONLY place a token is turned into a safe, loggable form.
function maskToken(token: string): string {
  return token.length > 8 ? `${token.slice(0, 4)}…${token.slice(-4)}` : "****";
}

// Masked token is DEV-console only — never sent to analytics/Sentry.
function devLog(message: string, token?: string): void {
  if (process.env.NODE_ENV === "production") return;
  console.log(token ? `[Push] ${message} (${maskToken(token)})` : `[Push] ${message}`);
}

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

// Idempotent. Registers + persists the FCM token ONLY if permission is already
// granted. Never shows the native prompt. Safe to call repeatedly and from
// multiple places (auth boot, login, card) — concurrent calls share one op.
// The inFlight check/assignment is synchronous (no await before it) so two
// concurrent callers can never spawn two operations.
export function ensurePushTokenRegistered(
  source: PushRegistrationSource,
): Promise<PushRegistrationResult> {
  if (inFlight) return inFlight;
  inFlight = runRegistration(source).finally(() => {
    inFlight = null;
  });
  return inFlight;
}

// Called on login / app boot. Thin wrapper — permission-gated by ensure().
export async function syncPushIfGranted(
  source: PushRegistrationSource = "auth_boot",
): Promise<PushRegistrationResult> {
  return ensurePushTokenRegistered(source);
}

// Called from the pre-permission card when the user taps "Ativar lembretes".
// Shows the native prompt when needed, then registers + persists the token.
export async function requestPushPermissionAndRegister(): Promise<PushRegistrationResult> {
  if (!(await isNative())) {
    return { permissionState: "unsupported", registered: false, failureReason: "unsupported" };
  }
  const { PushNotifications } = await import("@capacitor/push-notifications");
  markRequested();

  let status = await PushNotifications.checkPermissions();
  if (status.receive === "prompt" || status.receive === "prompt-with-rationale") {
    status = await PushNotifications.requestPermissions();
  }

  const permissionState = mapState(status.receive);
  if (permissionState !== "granted") {
    return { permissionState, registered: false, failureReason: "permission_denied" };
  }
  return ensurePushTokenRegistered("prepermission_card");
}

// ---------------------------------------------------------------------------
// Registration operation — single owner of the backend sync
// ---------------------------------------------------------------------------
async function runRegistration(source: PushRegistrationSource): Promise<PushRegistrationResult> {
  if (!(await isNative())) {
    return { permissionState: "unsupported", registered: false, failureReason: "unsupported" };
  }
  const permissionState = await getPushPermissionState();
  trackPushEvent("push_permission_state", { source, permission_status: permissionState });
  if (permissionState !== "granted") {
    return { permissionState, registered: false, failureReason: "permission_denied" };
  }

  const meta = await deviceMetadata();
  trackPushEvent("push_registration_started", { source, ...meta });

  await attachPermanentListeners();
  await ensureChannel();

  let token: string;
  try {
    token = await awaitRegistrationToken();
  } catch (err) {
    if (err instanceof RegistrationTimeout) {
      trackPushEvent("push_registration_timeout", { source, ...meta });
      return { permissionState: "granted", registered: false, failureReason: "registration_timeout" };
    }
    const category = err instanceof Error ? err.message : "unknown";
    trackPushEvent("push_registration_error", { source, ...meta, error_category: category });
    return { permissionState: "granted", registered: false, failureReason: "registration_error" };
  }

  trackPushEvent("push_registration_callback_received", { source, ...meta });
  devLog("registration token received", token);
  lastMaskedToken = maskToken(token);
  lastRegistrationAt = new Date().toISOString();

  const synced = await syncToken(token, source, meta);
  return {
    permissionState: "granted",
    registered: synced,
    failureReason: synced ? undefined : "backend_sync_failed",
  };
}

class RegistrationTimeout extends Error {
  constructor() {
    super("registration_timeout");
    this.name = "RegistrationTimeout";
  }
}

type ListenerHandle = { remove: () => Promise<void> };

// Attaches per-operation `registration`/`registrationError` listeners, then calls
// PushNotifications.register() and resolves with the token. The listeners are
// removed on success, error and timeout — so a delayed callback from a timed-out
// attempt can never resolve a later attempt. Only one op runs at a time.
async function awaitRegistrationToken(): Promise<string> {
  const { PushNotifications } = await import("@capacitor/push-notifications");

  let regHandle: ListenerHandle | undefined;
  let errHandle: ListenerHandle | undefined;
  let settled = false;
  let timer: ReturnType<typeof setTimeout> | undefined;

  const cleanup = () => {
    if (timer) clearTimeout(timer);
    void regHandle?.remove();
    void errHandle?.remove();
  };

  return new Promise<string>((resolve, reject) => {
    const settle = (fn: () => void) => {
      if (settled) return;
      settled = true;
      cleanup();
      fn();
    };

    timer = setTimeout(() => settle(() => reject(new RegistrationTimeout())), REGISTRATION_TIMEOUT_MS);

    // Attach BOTH listeners before register() so the token event can't be missed.
    Promise.all([
      PushNotifications.addListener("registration", ({ value }) => settle(() => resolve(value))),
      PushNotifications.addListener("registrationError", (err) =>
        settle(() => reject(new Error(err?.error ?? "registration_error"))),
      ),
    ])
      .then(([reg, errListener]) => {
        regHandle = reg;
        errHandle = errListener;
        // If the op already settled (fast event or timeout) before the handles
        // resolved, remove them now so nothing leaks.
        if (settled) {
          void reg.remove();
          void errListener.remove();
          return undefined;
        }
        return PushNotifications.register();
      })
      .catch((e) => settle(() => reject(e instanceof Error ? e : new Error("register_failed"))));
  });
}

// Posts the token to the backend with one short retry for transient failures
// (network / 5xx). 4xx is not retried. Returns whether it persisted.
async function syncToken(
  token: string,
  source: PushRegistrationSource,
  meta: Awaited<ReturnType<typeof deviceMetadata>>,
): Promise<boolean> {
  trackPushEvent("push_backend_sync_started", { source, ...meta });

  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      await api.post("/api/v1/device_tokens", {
        token,
        platform: "android",
        permission_status: "granted",
        ...meta,
      });
      trackPushEvent("push_backend_sync_succeeded", { source, ...meta });
      devLog("backend sync succeeded", token);
      lastTokenSyncedToApi = true;
      lastApiStatus = "ok";
      return true;
    } catch (err) {
      const status = err instanceof ApiError ? err.status : undefined;
      const transient = status === undefined || status >= 500;
      const lastAttempt = attempt === 1 || !transient;
      if (lastAttempt) {
        trackPushEvent("push_backend_sync_failed", {
          source,
          ...meta,
          http_status: status,
          error_category: transient ? "transient" : "client_error",
        });
        lastTokenSyncedToApi = false;
        lastApiStatus = status ?? null;
        return false;
      }
      // one short retry for transient failures
      await new Promise((r) => setTimeout(r, 800));
    }
  }
  return false;
}

async function deviceMetadata(): Promise<{ app_version?: string; os_version?: string }> {
  const meta: { app_version?: string; os_version?: string } = {};
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

// Permanent listeners: foreground receipt + tap routing. Attached once; NEVER
// removed during a registration operation (removeAllListeners is not used).
async function attachPermanentListeners(): Promise<void> {
  if (permanentListenersAttached) return;
  permanentListenersAttached = true;

  const { PushNotifications } = await import("@capacitor/push-notifications");
  await PushNotifications.addListener("pushNotificationReceived", (notification) => {
    devLog(`foreground notification: ${notification.title ?? ""}`);
    lastForeground = { title: notification.title ?? null, at: new Date().toISOString() };
  });
  await PushNotifications.addListener("pushNotificationActionPerformed", (action) => {
    void handleActionPerformed(action.notification?.data ?? {});
  });
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
  lastAction = { path, type: data.type != null ? String(data.type) : null, at: new Date().toISOString() };
  // Carry the delivery id so the target screen can offer "não gostei" feedback.
  const target = deliveryId != null ? `${path}${path.includes("?") ? "&" : "?"}from_push=${deliveryId}` : path;
  if (typeof window !== "undefined") window.location.assign(target);
}

// ---------------------------------------------------------------------------
// Device diagnostics (admin-only panel). All read-only/report helpers here are
// safe on the web (they no-op / return "unsupported") and never expose the raw
// token — only the mask captured during registration.
// ---------------------------------------------------------------------------

export async function collectPushDiagnostics(): Promise<PushDiagnosticsSnapshot> {
  const native = await isNative();
  let platform = "web";
  try {
    const { Capacitor } = await import("@capacitor/core");
    platform = Capacitor.getPlatform();
  } catch {
    /* ignore */
  }
  const permissionState = native ? await getPushPermissionState() : "unsupported";
  const meta = await deviceMetadata();
  let build: string | null = null;
  try {
    const { App } = await import("@capacitor/app");
    const info = await App.getInfo();
    build = info.build ?? null;
  } catch {
    /* @capacitor/app may be unavailable */
  }
  return {
    platform,
    isNative: native,
    permissionState,
    maskedToken: lastMaskedToken,
    tokenSyncedToApi: lastTokenSyncedToApi,
    lastApiStatus,
    lastRegistrationAt,
    channelId: "workout_reminders",
    appVersion: meta.app_version ?? null,
    build,
    firebaseHint: "FCM project is configured server-side; not exposed to the client.",
    lastForeground,
    lastAction,
  };
}

// Opens the OS notification settings for this app (Android). Returns false on web
// or if the native plugin is unavailable.
export async function openAppNotificationSettings(): Promise<boolean> {
  if (!(await isNative())) return false;
  try {
    const { NativeSettings, AndroidSettings } = await import("capacitor-native-settings");
    await NativeSettings.openAndroid({ option: AndroidSettings.AppNotification });
    trackPushEvent("push_open_settings_invoked", {});
    return true;
  } catch {
    return false;
  }
}

// Fires an immediate LOCAL notification (no server / FCM) so we can isolate an
// on-device display problem from a delivery problem. Android-only.
export async function sendLocalTestNotification(): Promise<boolean> {
  if (!(await isNative())) return false;
  try {
    const { LocalNotifications } = await import("@capacitor/local-notifications");
    let perm = await LocalNotifications.checkPermissions();
    if (perm.display !== "granted") {
      perm = await LocalNotifications.requestPermissions();
      if (perm.display !== "granted") return false;
    }
    try {
      await LocalNotifications.createChannel({
        id: "workout_reminders",
        name: "Lembretes de treino",
        importance: 4,
        visibility: 1,
      });
    } catch {
      /* channel best-effort */
    }
    await LocalNotifications.schedule({
      notifications: [
        {
          id: Date.now() % 100000,
          title: "Teste local EasyHealth",
          body: "Notificação local de diagnóstico (não passou pelo Firebase).",
          channelId: "workout_reminders",
          extra: { type: "admin_push_test_local" },
        },
      ],
    });
    trackPushEvent("push_local_test_scheduled", {});
    return true;
  } catch {
    return false;
  }
}

// Asks the backend to send the admin test push to THIS user's own tokens. The
// endpoint is admin-only and self-only; no user id is ever sent.
export async function requestApiTestPush(): Promise<{ ok: boolean; status?: number; errorCode?: string; body?: unknown }> {
  try {
    const body = await api.post("/api/v1/admin/push_test", {});
    return { ok: true, body };
  } catch (err) {
    if (err instanceof ApiError) return { ok: false, status: err.status, errorCode: err.errorCode };
    return { ok: false };
  }
}

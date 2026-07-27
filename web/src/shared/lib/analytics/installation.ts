import * as Sentry from "@sentry/nextjs";
import { api, ApiError } from "../api";
import {
  detectPlatform,
  getAnalyticsContext,
  getCachedInstallationId,
  isNativeApp,
  setCachedInstallationId,
} from "./context";

// installation_id — a stable, random UUID identifying ONE app installation.
//
// - Created once, persisted in @capacitor/preferences on native (survives
//   localStorage/WebView data clears) with a localStorage mirror on web.
// - Survives logout; only a reinstall (storage wiped) creates a new one.
// - NEVER derived from Advertising ID, Android ID, the FCM token, email or user_id.
//
// Backed by the app_installations backend (POST /api/v1/app/installations/register).

const PREF_KEY = "eh_installation_id";
// Default-ON kill-switch: tracking runs unless explicitly disabled. Only "false"
// turns it off — an unset/empty env keeps it enabled (a build-time env that was
// silently never set is exactly what kept this dark in production).
const MOBILE_ANALYTICS_ENABLED =
  process.env.NEXT_PUBLIC_MOBILE_ANALYTICS_ENABLED !== "false";

// Concurrency guard: a single in-flight resolution so a burst of callers on boot
// can never generate two UUIDs.
let resolving: Promise<string> | null = null;

function uuid(): string {
  try {
    if (typeof crypto !== "undefined" && crypto.randomUUID) return crypto.randomUUID();
  } catch {
    /* fall through */
  }
  return `eh-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

async function readPersisted(): Promise<string | null> {
  // Prefer the durable native store; fall back to the localStorage mirror.
  if (isNativeApp()) {
    try {
      const { Preferences } = await import("@capacitor/preferences");
      const { value } = await Preferences.get({ key: PREF_KEY });
      if (value) return value;
    } catch {
      /* plugin unavailable — fall back to mirror */
    }
  }
  return getCachedInstallationId() ?? null;
}

async function writePersisted(id: string): Promise<void> {
  setCachedInstallationId(id); // localStorage mirror + in-memory cache
  if (isNativeApp()) {
    try {
      const { Preferences } = await import("@capacitor/preferences");
      await Preferences.set({ key: PREF_KEY, value: id });
    } catch {
      /* plugin unavailable — mirror is best-effort persistence */
    }
  }
}

// Returns the installation_id, creating and persisting it on first call.
export async function getInstallationId(): Promise<string> {
  const cached = getCachedInstallationId();
  if (cached) return cached;
  if (resolving) return resolving;

  resolving = (async () => {
    const existing = await readPersisted();
    if (existing) {
      setCachedInstallationId(existing);
      return existing;
    }
    const created = uuid();
    await writePersisted(created);
    return created;
  })();

  try {
    return await resolving;
  } finally {
    resolving = null;
  }
}

export function getInstallationIdSync(): string | undefined {
  return getCachedInstallationId();
}

// Low-cardinality, non-PII device facts for the installation record only.
interface DeviceContext {
  operating_system?: string;
  operating_system_version?: string;
  device_manufacturer?: string;
  device_model?: string;
}

async function getDeviceContext(): Promise<DeviceContext> {
  if (!isNativeApp()) return {};
  try {
    const { Device } = await import("@capacitor/device");
    const info = await Device.getInfo();
    return {
      operating_system: info.operatingSystem,
      operating_system_version: info.osVersion,
      device_manufacturer: info.manufacturer,
      device_model: info.model,
    };
  } catch {
    return {};
  }
}

async function getAppBuild(): Promise<{ app_version?: string; app_build?: string }> {
  if (!isNativeApp()) return {};
  try {
    const { App } = await import("@capacitor/app");
    const info = await App.getInfo();
    return { app_version: info.version, app_build: info.build };
  } catch {
    return {};
  }
}

export interface InstallationOverrides {
  notification_permission?: string;
  push_enabled?: boolean;
  analytics_consent?: boolean;
}

export interface RegisterOptions {
  // True only when the call represents a genuine native session start (app boot).
  sessionStarted?: boolean;
}

async function buildPayload(
  overrides: InstallationOverrides,
  opts: RegisterOptions = {}
) {
  const [installation_id, device, appInfo] = await Promise.all([
    getInstallationId(),
    getDeviceContext(),
    getAppBuild(),
  ]);
  const ctx = getAnalyticsContext();

  return {
    installation_id,
    platform: detectPlatform(),
    native: isNativeApp(),
    app_version: appInfo.app_version ?? ctx.app_version,
    app_build: appInfo.app_build ?? ctx.build_number,
    locale: ctx.locale,
    timezone: ctx.timezone,
    tracking_version: TRACKING_VERSION,
    // Only a real native session start (app boot) stamps last_session_at server-side.
    // A post-login re-register is NOT a new session and must omit this.
    ...(opts.sessionStarted ? { session_started: true } : {}),
    ...device,
    ...overrides,
  };
}

export const TRACKING_VERSION = 2;

export type InstallationFailureCode =
  | "disabled"
  | "unsupported"
  | "id_unavailable"
  | "transient"
  | "client_error";

export interface EnsureInstallationResult {
  // Present whenever the local id could be resolved, even if the backend call
  // failed — the caller can still send X-Installation-Id and let the backend
  // reconcile on a later authenticated request.
  installationId: string | null;
  remoteRegistered: boolean;
  failureCode?: InstallationFailureCode;
}

// A successful remote register is remembered for the app cycle so a resume or a
// login does not re-POST. A FAILED one is not, so those are exactly the moments
// that retry it.
let remoteRegistered = false;
// Shared in-flight operation: boot, login, push and resume can all call this at
// once and must never produce concurrent registrations.
let ensuring: Promise<EnsureInstallationResult> | null = null;

// How long an auth flow is willing to wait for the remote register before going
// ahead. The local id is always awaited (it is fast and local); only the network
// leg is time-boxed, so a slow backend can never delay a login.
const AUTH_REGISTER_BUDGET_MS = 2_000;

// Posts the register upsert with one short retry for transient failures
// (network / 5xx), mirroring the device-token sync. 4xx is never retried: the
// payload itself is the problem and a repeat would fail identically.
async function postRegister(
  overrides: InstallationOverrides,
  opts: RegisterOptions
): Promise<{ ok: boolean; failureCode?: InstallationFailureCode }> {
  const payload = await buildPayload(overrides, opts);

  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      await api.post("/api/v1/app/installations/register", payload);
      return { ok: true };
    } catch (err) {
      const status = err instanceof ApiError ? err.status : undefined;
      const transient = status === undefined || status >= 500;
      if (!transient) return { ok: false, failureCode: "client_error" };
      if (attempt === 1) return { ok: false, failureCode: "transient" };
      await new Promise((resolve) => setTimeout(resolve, 800));
    }
  }
  return { ok: false, failureCode: "transient" };
}

// Guarantees the installation exists locally and, when possible, on the backend.
//
// Best-effort by contract: a failure here defers the link to the next
// authenticated request (the backend reconciles continuously), so no caller may
// treat it as fatal. Android-only — web/PWA does not carry an installation.
export function ensureInstallationRegistered(
  overrides: InstallationOverrides = {},
  opts: RegisterOptions = {}
): Promise<EnsureInstallationResult> {
  if (typeof window === "undefined" || !MOBILE_ANALYTICS_ENABLED) {
    return Promise.resolve({ installationId: null, remoteRegistered: false, failureCode: "disabled" });
  }
  if (!isNativeApp()) {
    return Promise.resolve({ installationId: null, remoteRegistered: false, failureCode: "unsupported" });
  }
  // Already done for this app cycle: return the known id without a network call.
  if (remoteRegistered) {
    return Promise.resolve({ installationId: getCachedInstallationId() ?? null, remoteRegistered: true });
  }
  // The check and the assignment are synchronous (no await between them), so
  // concurrent callers can never spawn two operations.
  if (ensuring) return ensuring;

  ensuring = runEnsure(overrides, opts).finally(() => {
    ensuring = null;
  });
  return ensuring;
}

async function runEnsure(
  overrides: InstallationOverrides,
  opts: RegisterOptions
): Promise<EnsureInstallationResult> {
  let installationId: string | null = null;
  try {
    installationId = await getInstallationId();
  } catch {
    // Storage unavailable: nothing else can work, but the caller must continue.
    return { installationId: null, remoteRegistered: false, failureCode: "id_unavailable" };
  }

  const result = await postRegister(overrides, opts);
  if (result.ok) {
    remoteRegistered = true;
    return { installationId, remoteRegistered: true };
  }

  breadcrumb("installation_register_failed", { failure_code: result.failureCode });
  return { installationId, remoteRegistered: false, failureCode: result.failureCode };
}

// For authentication flows. Awaits the local id (so X-Installation-Id is on the
// sign-in request itself) but time-boxes the network leg: login must never wait
// on tracking. The registration keeps running in the background either way.
export async function ensureInstallationForAuth(): Promise<EnsureInstallationResult> {
  const pending = ensureInstallationRegistered();

  const budget = new Promise<EnsureInstallationResult>((resolve) => {
    setTimeout(
      () => resolve({
        installationId: getCachedInstallationId() ?? null,
        remoteRegistered: false,
        failureCode: "transient",
      }),
      AUTH_REGISTER_BUDGET_MS
    );
  });

  try {
    return await Promise.race([ pending, budget ]);
  } catch {
    return { installationId: getCachedInstallationId() ?? null, remoteRegistered: false, failureCode: "transient" };
  }
}

// Leaves a trail in Sentry so a systemic tracking outage is visible, without
// turning a best-effort call into a reported error.
function breadcrumb(message: string, data: Record<string, unknown>): void {
  try {
    Sentry.addBreadcrumb({ category: "installation", level: "warning", message, data });
  } catch {
    /* Sentry not initialized — ignore */
  }
}

// @deprecated Use ensureInstallationRegistered — it is single-flight, retries a
// transient failure and reports whether the backend actually has the install.
export async function registerInstallation(
  overrides: InstallationOverrides = {},
  opts: RegisterOptions = {}
): Promise<void> {
  await ensureInstallationRegistered(overrides, opts);
}

// Refresh mutable fields (permission/consent/version) for an existing install.
export async function refreshInstallation(
  overrides: InstallationOverrides = {}
): Promise<void> {
  if (typeof window === "undefined" || !MOBILE_ANALYTICS_ENABLED) return;
  try {
    const id = await getInstallationId();
    const payload = await buildPayload(overrides);
    await api.patch(`/api/v1/app/installations/${encodeURIComponent(id)}`, payload);
  } catch {
    /* swallow */
  }
}

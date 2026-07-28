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

// The local id is awaited before authentication, so a native plugin that never
// answers must not hold the login forever. Slow is fine (the real stored id is
// worth waiting for); hung falls back to the localStorage mirror.
const LOCAL_STORE_BUDGET_MS = 3_000;

function withBudget<T>(work: Promise<T>, fallback: T): Promise<T> {
  return new Promise<T>((resolve) => {
    const timer = setTimeout(() => resolve(fallback), LOCAL_STORE_BUDGET_MS);
    work.then(
      (value) => { clearTimeout(timer); resolve(value); },
      () => { clearTimeout(timer); resolve(fallback); }
    );
  });
}

async function readPersisted(): Promise<string | null> {
  // Prefer the durable native store; fall back to the localStorage mirror.
  if (isNativeApp()) {
    const stored = await withBudget<string | null>(
      (async () => {
        const { Preferences } = await import("@capacitor/preferences");
        const { value } = await Preferences.get({ key: PREF_KEY });
        return value ?? null;
      })(),
      null // plugin unavailable or hung — fall back to mirror
    );
    if (stored) return stored;
  }
  return getCachedInstallationId() ?? null;
}

async function writePersisted(id: string): Promise<void> {
  setCachedInstallationId(id); // localStorage mirror + in-memory cache
  if (isNativeApp()) {
    await withBudget<void>(
      (async () => {
        const { Preferences } = await import("@capacitor/preferences");
        await Preferences.set({ key: PREF_KEY, value: id });
      })(),
      undefined // mirror is best-effort persistence on its own
    );
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
  | "client_error"
  | "deferred";

// What the backend actually did with the installation, straight from the
// response contract. "registered" is the ONLY value that means the row exists.
export type InstallationRemoteStatus = "registered" | "deferred" | "disabled" | "failed";

export interface EnsureInstallationResult {
  // Present whenever the local id could be resolved, even if the backend call
  // failed — the caller can still send X-Installation-Id and let the backend
  // reconcile on a later authenticated request.
  installationId: string | null;
  remoteRegistered: boolean;
  remoteStatus: InstallationRemoteStatus;
  failureCode?: InstallationFailureCode;
}

// The register response contract (see Api::V1::App::InstallationsController).
interface RegisterResponse {
  status?: string;
  registered?: boolean;
  retryable?: boolean;
  installation_id?: string;
  created?: boolean;
  link_status?: string | null;
}

// A registration is claimed only when the backend says the row exists. A 202
// (deferred/disabled) is a 2xx that wrote nothing — treating it as success is
// what silently suppressed retries for the rest of the app cycle.
function isRegistered(body: RegisterResponse | null | undefined): boolean {
  if (!body) return false;
  if (body.registered === true || body.status === "registered") return true;
  // Compatibility with a backend that predates the contract: its success body
  // echoed the installation_id and its 202 had no body at all.
  return body.status === undefined && typeof body.installation_id === "string";
}

// A successful remote register is remembered for the app cycle so a resume or a
// login does not re-POST. A FAILED one is not, so those are exactly the moments
// that retry it.
let remoteRegistered = false;
// The backend answered "disabled": the flag is off server-side, so re-POSTing
// on every resume only burns requests. Not a success — remoteRegistered stays
// false and nothing is ever reported as registered.
let remoteDisabled = false;
// Payload the backend rejected with a 4xx. Retried only if the metadata itself
// changes; an identical body would be rejected identically.
let rejectedPayloadKey: string | null = null;
// Shared in-flight operation: boot, login, push and resume can all call this at
// once and must never produce concurrent registrations.
let ensuring: Promise<EnsureInstallationResult> | null = null;

// How long an auth flow is willing to wait for the remote register before going
// ahead. The local id is always awaited (it is fast and local); only the network
// leg is time-boxed, so a slow backend can never delay a login.
const AUTH_REGISTER_BUDGET_MS = 2_000;

const REGISTER_PATH = "/api/v1/app/installations/register";

// 4xx means "this payload is wrong" and is never retried — except for the codes
// that describe the moment rather than the request.
function isTransientStatus(status: number | undefined): boolean {
  if (status === undefined) return true; // network/abort
  if (status === 408 || status === 425 || status === 429) return true;
  return status >= 500;
}

// Posts the register upsert with one short retry for transient failures
// (network / 5xx), mirroring the device-token sync.
//
// The reply is read from the BODY, not from the status class: the endpoint
// answers 202 with `status: "deferred"` when it wrote nothing, so a 2xx alone
// proves nothing about the installation existing.
async function postRegister(
  overrides: InstallationOverrides,
  opts: RegisterOptions
): Promise<{ status: InstallationRemoteStatus; failureCode?: InstallationFailureCode }> {
  const payload = await buildPayload(overrides, opts);
  const payloadKey = JSON.stringify(payload);

  // The backend already rejected exactly this metadata. Retry only once it
  // changes, instead of re-sending a body known to be invalid.
  if (rejectedPayloadKey === payloadKey) {
    return { status: "failed", failureCode: "client_error" };
  }

  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const body = await api.post<RegisterResponse>(REGISTER_PATH, payload);

      if (isRegistered(body)) return { status: "registered" };

      if (body?.status === "disabled") {
        remoteDisabled = true;
        return { status: "disabled", failureCode: "disabled" };
      }

      // Accepted but not stored. An immediate repeat would meet the same
      // backend state, so the retry belongs to the next cycle (resume or the
      // next authentication), never to this loop.
      return { status: "deferred", failureCode: "deferred" };
    } catch (err) {
      const status = err instanceof ApiError ? err.status : undefined;
      if (!isTransientStatus(status)) {
        rejectedPayloadKey = payloadKey;
        return { status: "failed", failureCode: "client_error" };
      }
      if (attempt === 1) return { status: "failed", failureCode: "transient" };
      await new Promise((resolve) => setTimeout(resolve, 800));
    }
  }
  return { status: "failed", failureCode: "transient" };
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
    return Promise.resolve(inactiveResult("disabled"));
  }
  if (!isNativeApp()) {
    return Promise.resolve(inactiveResult("unsupported"));
  }
  // Already done for this app cycle: return the known id without a network call.
  if (remoteRegistered) {
    return Promise.resolve({
      installationId: getCachedInstallationId() ?? null,
      remoteRegistered: true,
      remoteStatus: "registered",
    });
  }
  // The backend said the feature is off. Keep the local id, keep reporting it as
  // NOT registered, and stop paying for a POST that answers "disabled" forever.
  if (remoteDisabled) {
    return Promise.resolve({
      installationId: getCachedInstallationId() ?? null,
      remoteRegistered: false,
      remoteStatus: "disabled",
      failureCode: "disabled",
    });
  }
  // The check and the assignment are synchronous (no await between them), so
  // concurrent callers can never spawn two operations.
  if (ensuring) return ensuring;

  ensuring = runEnsure(overrides, opts).finally(() => {
    ensuring = null;
  });
  return ensuring;
}

// Nothing to register (SSR, flag off, or a browser): there is no installation
// at all, so there is no id and nothing to retry.
function inactiveResult(failureCode: InstallationFailureCode): EnsureInstallationResult {
  return { installationId: null, remoteRegistered: false, remoteStatus: "disabled", failureCode };
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
    return {
      installationId: null,
      remoteRegistered: false,
      remoteStatus: "failed",
      failureCode: "id_unavailable",
    };
  }

  const result = await postRegister(overrides, opts);
  if (result.status === "registered") {
    remoteRegistered = true;
    return { installationId, remoteRegistered: true, remoteStatus: "registered" };
  }

  // Not registered — including a 202 the old code counted as success.
  breadcrumb("installation_register_unconfirmed", {
    remote_status: result.status,
    failure_code: result.failureCode,
  });
  return {
    installationId,
    remoteRegistered: false,
    remoteStatus: result.status,
    failureCode: result.failureCode,
  };
}

// For authentication flows. Two legs with different rules:
//
//   1. the LOCAL id is always awaited — it is storage-only, it is what puts
//      X-Installation-Id on the sign-in request itself, and it is NOT inside
//      the network budget (a slow Preferences read used to eat the whole 2s and
//      send the first login with no header);
//   2. the REMOTE register is time-boxed — login must never wait on tracking.
//
// The register keeps running in the background when the budget expires, and its
// outcome is reported separately from the id: remoteRegistered/remoteStatus.
export async function ensureInstallationForAuth(): Promise<EnsureInstallationResult> {
  if (typeof window === "undefined" || !MOBILE_ANALYTICS_ENABLED) return inactiveResult("disabled");
  if (!isNativeApp()) return inactiveResult("unsupported");

  let installationId: string | null;
  try {
    installationId = await getInstallationId();
  } catch {
    // No local id: auth still proceeds, the backend links on a later request.
    return {
      installationId: null,
      remoteRegistered: false,
      remoteStatus: "failed",
      failureCode: "id_unavailable",
    };
  }

  const pending = ensureInstallationRegistered();

  const budget = new Promise<EnsureInstallationResult>((resolve) => {
    setTimeout(
      () => resolve({
        installationId,
        remoteRegistered: false,
        // Still in flight, not failed: the next cycle retries it if it loses.
        remoteStatus: "deferred",
        failureCode: "transient",
      }),
      AUTH_REGISTER_BUDGET_MS
    );
  });

  try {
    const result = await Promise.race([ pending, budget ]);
    // The id is known here even when the remote leg returned nothing.
    return { ...result, installationId: result.installationId ?? installationId };
  } catch {
    return {
      installationId,
      remoteRegistered: false,
      remoteStatus: "failed",
      failureCode: "transient",
    };
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

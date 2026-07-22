import { Capacitor } from "@capacitor/core";
import { api } from "../api";
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
const MOBILE_ANALYTICS_ENABLED =
  process.env.NEXT_PUBLIC_MOBILE_ANALYTICS_ENABLED === "true";

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

async function buildPayload(overrides: InstallationOverrides) {
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
    ...device,
    ...overrides,
  };
}

export const TRACKING_VERSION = 2;

// Register (upsert) the installation. Non-blocking and best-effort: tracking must
// never break the boot. Associates to the user automatically when the session
// cookie is present (the backend reads current_user; never trusts a client id).
export async function registerInstallation(
  overrides: InstallationOverrides = {}
): Promise<void> {
  if (typeof window === "undefined" || !MOBILE_ANALYTICS_ENABLED) return;
  try {
    const payload = await buildPayload(overrides);
    await api.post("/api/v1/app/installations/register", payload);
  } catch {
    /* swallow — endpoint is fire-and-forget, backend logs failures */
  }
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

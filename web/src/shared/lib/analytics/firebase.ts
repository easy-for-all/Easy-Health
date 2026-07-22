import { isNativeApp } from "./context";

// Native Firebase bridge (Analytics / Crashlytics / Performance) via
// @capacitor-firebase/*. WebView note: the app loads the remote site, so on
// web/PWA these are NO-OPS — GA4 handles the web (see routing in index.ts).
// Everything here is best-effort: analytics must never break the app, and NO PII
// ever reaches Firebase (allowlist enforced below).

export const FIREBASE_ANALYTICS_ENABLED =
  process.env.NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED === "true";
export const FIREBASE_CRASHLYTICS_ENABLED =
  process.env.NEXT_PUBLIC_FIREBASE_CRASHLYTICS_ENABLED === "true";
export const FIREBASE_PERFORMANCE_ENABLED =
  process.env.NEXT_PUBLIC_FIREBASE_PERFORMANCE_ENABLED === "true";

export function firebaseAnalyticsActive(): boolean {
  return isNativeApp() && FIREBASE_ANALYTICS_ENABLED;
}

// Only these user properties may be set on Firebase — never medical/PII data.
const ALLOWED_USER_PROPERTIES = new Set([
  "subscription_status",
  "onboarding_flow",
  "experience_level",
  "app_language",
  "app_version_group",
]);

// Property keys that must NEVER be sent anywhere near Firebase.
const FORBIDDEN_PROPERTY_KEYS = new Set([
  "email", "name", "phone", "cpf", "medical_data", "injury",
  "limitation_text", "coach_message", "access_token", "refresh_token", "fcm_token",
]);

function sanitize(params?: Record<string, unknown>): Record<string, unknown> {
  if (!params) return {};
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(params)) {
    if (FORBIDDEN_PROPERTY_KEYS.has(k) || v === undefined) continue;
    out[k] = v;
  }
  return out;
}

let initialized = false;

export async function initFirebase(consentGranted: boolean): Promise<void> {
  if (!isNativeApp() || initialized) return;
  initialized = true;

  if (FIREBASE_ANALYTICS_ENABLED) {
    try {
      const { FirebaseAnalytics } = await import("@capacitor-firebase/analytics");
      await FirebaseAnalytics.setEnabled({ enabled: consentGranted });
    } catch {
      /* plugin unavailable — no-op */
    }
  }
  if (FIREBASE_CRASHLYTICS_ENABLED) {
    try {
      const { FirebaseCrashlytics } = await import("@capacitor-firebase/crashlytics");
      await FirebaseCrashlytics.setEnabled({ enabled: true });
    } catch {
      /* no-op */
    }
  }
}

// Reflect a consent change onto Firebase Analytics collection.
export async function setFirebaseAnalyticsConsent(granted: boolean): Promise<void> {
  if (!firebaseAnalyticsActive()) return;
  try {
    const { FirebaseAnalytics } = await import("@capacitor-firebase/analytics");
    await FirebaseAnalytics.setEnabled({ enabled: granted });
  } catch {
    /* no-op */
  }
}

export async function logFirebaseEvent(
  name: string,
  params?: Record<string, unknown>
): Promise<void> {
  if (!firebaseAnalyticsActive()) return;
  try {
    const { FirebaseAnalytics } = await import("@capacitor-firebase/analytics");
    await FirebaseAnalytics.logEvent({ name, params: sanitize(params) });
  } catch {
    /* no-op */
  }
}

export async function setFirebaseScreen(screenName: string): Promise<void> {
  if (!firebaseAnalyticsActive()) return;
  try {
    const { FirebaseAnalytics } = await import("@capacitor-firebase/analytics");
    await FirebaseAnalytics.setCurrentScreen({ screenName });
  } catch {
    /* no-op */
  }
}

// Pseudonymous internal id ONLY (never email / installation_id).
export async function setFirebaseUserId(userId: string | null): Promise<void> {
  if (!isNativeApp()) return;
  try {
    if (FIREBASE_ANALYTICS_ENABLED) {
      const { FirebaseAnalytics } = await import("@capacitor-firebase/analytics");
      await FirebaseAnalytics.setUserId({ userId });
    }
    if (FIREBASE_CRASHLYTICS_ENABLED && userId) {
      const { FirebaseCrashlytics } = await import("@capacitor-firebase/crashlytics");
      await FirebaseCrashlytics.setUserId({ userId });
    }
  } catch {
    /* no-op */
  }
}

export async function setFirebaseUserProperty(key: string, value: string): Promise<void> {
  if (!firebaseAnalyticsActive() || !ALLOWED_USER_PROPERTIES.has(key)) return;
  try {
    const { FirebaseAnalytics } = await import("@capacitor-firebase/analytics");
    await FirebaseAnalytics.setUserProperty({ key, value });
  } catch {
    /* no-op */
  }
}

// Non-fatal exception to Crashlytics (native crashes/ANRs are captured
// automatically). Message must not carry PII.
export async function recordCrashlyticsException(message: string): Promise<void> {
  if (!isNativeApp() || !FIREBASE_CRASHLYTICS_ENABLED) return;
  try {
    const { FirebaseCrashlytics } = await import("@capacitor-firebase/crashlytics");
    await FirebaseCrashlytics.recordException({ message });
  } catch {
    /* no-op */
  }
}

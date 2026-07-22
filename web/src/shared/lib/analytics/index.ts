import {
  detectEnvironment,
  getAnalyticsContext,
  getAnonymousId,
  setUserId,
  startAnalyticsSession as startSession,
} from "./context";
import {
  CLARITY_CUSTOM_TAG_EVENTS,
  EventName,
  isKnownEvent,
} from "./taxonomy";
import { enqueueServerEvent, isServerEvent } from "./server";
import { registerInstallation } from "./installation";
import {
  firebaseAnalyticsActive,
  logFirebaseEvent,
  setFirebaseScreen,
  setFirebaseUserId,
} from "./firebase";

declare global {
  interface Window {
    gtag?: (...args: unknown[]) => void;
    clarity?: (...args: unknown[]) => void;
  }
}

type EventParams = Record<string, string | number | boolean | undefined>;
export type BillingPlanName = "pro_monthly" | "pro_yearly";

// Analytics must never emit to real sinks from an automated test run.
function sinksEnabled(): boolean {
  return detectEnvironment() !== "test";
}

const CLARITY_SET = new Set<string>(CLARITY_CUSTOM_TAG_EVENTS as string[]);

function sendClarityEvent(name: string): void {
  if (typeof window === "undefined" || typeof window.clarity !== "function") return;
  try {
    window.clarity("event", name);
  } catch {
    /* diagnostics only — never throw */
  }
}

// Central dispatch. Behavioural events go to GA4 (as before); events whose
// taxonomy sink includes "server" are ALSO persisted in the backend; a subset
// is mirrored to Clarity as custom tags. Unknown names still reach GA4 so no
// existing call site regresses.
export function trackEvent(eventName: string, params?: EventParams): void {
  if (typeof window === "undefined") return;
  if (process.env.NODE_ENV === "development") {
    console.log(`[Analytics] ${eventName}`, params ?? {});
  }
  if (!sinksEnabled()) return;

  // Destination routing (anti-duplication): Web/PWA -> GA4 (gtag). Native Android
  // with Firebase Analytics active -> Firebase native ONLY, and GA4 is suppressed
  // so the same event is not counted twice (WebView gtag + native SDK).
  const routeToFirebase = firebaseAnalyticsActive();
  if (typeof window.gtag === "function" && !routeToFirebase) {
    window.gtag("event", eventName, params);
  }
  if (routeToFirebase) {
    void logFirebaseEvent(eventName, params);
  }

  if (isKnownEvent(eventName)) {
    if (isServerEvent(eventName)) {
      enqueueServerEvent(eventName as EventName, 1, cleanProps(params));
    }
    if (CLARITY_SET.has(eventName)) sendClarityEvent(eventName);
  }
}

// Server-only auditable event (skips GA4). Used for lifecycle/push/experiment
// events that should not inflate GA4 behavioural reports.
export function trackServerEvent(
  eventName: EventName,
  properties: Record<string, unknown> = {}
): void {
  if (typeof window === "undefined" || !sinksEnabled()) return;
  if (isServerEvent(eventName)) enqueueServerEvent(eventName, 1, properties);
}

function cleanProps(params?: EventParams): Record<string, unknown> {
  if (!params) return {};
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined) out[k] = v;
  }
  return out;
}

// Idempotent tracking guard (React Strict Mode double-invoke, remounts).
const onceKeys = new Set<string>();
export function trackOnce(key: string, eventName: string, params?: EventParams): void {
  if (onceKeys.has(key)) return;
  onceKeys.add(key);
  trackEvent(eventName, params);
}

export function trackScreenView(screen: string, params?: EventParams): void {
  // Native screen tracking uses Firebase's dedicated setCurrentScreen; trackEvent
  // handles GA4 (web) vs Firebase-event (native) routing for the screen_view event.
  if (firebaseAnalyticsActive()) void setFirebaseScreen(screen);
  trackEvent("screen_view", { screen, ...params });
}

// Associate the anonymous thread with the authenticated user across sinks.
export function identifyUser(userId: string | number): void {
  const id = String(userId);
  setUserId(id);
  // Re-register the installation now that the session cookie is present, so the
  // backend associates this install to the user (last_authenticated_at). Safe on
  // web/PWA too — it no-ops off-native or when the feature flag is off.
  void registerInstallation();
  // Native: set a pseudonymous internal user id on Firebase (never email / installation_id).
  void setFirebaseUserId(id);
  if (typeof window === "undefined" || !sinksEnabled()) return;
  if (typeof window.gtag === "function") {
    window.gtag("set", { user_id: id });
  }
  if (typeof window.clarity === "function") {
    try {
      window.clarity("identify", getAnonymousId());
    } catch {
      /* ignore */
    }
  }
}

// On logout: drop the user_id but KEEP anonymous_id (same install/visitor).
export function resetIdentity(): void {
  setUserId(undefined);
  void setFirebaseUserId(null); // drop Firebase user id; installation_id is preserved
  if (typeof window !== "undefined" && typeof window.gtag === "function" && sinksEnabled()) {
    window.gtag("set", { user_id: null });
  }
}

export function startAnalyticsSession(): string {
  return startSession();
}

export { getAnalyticsContext };
export {
  getInstallationId,
  getInstallationIdSync,
  registerInstallation,
  refreshInstallation,
} from "./installation";

// send_to labels: get from Google Ads -> Conversions -> select action -> Tag setup
export const CONVERSIONS = {
  SIGNUP:       "AW-17759537883/-FCPCJ7mkrAcENuVtJRC",
  PAGE_VIEW:    "AW-17759537883/BIKACLyy67YcENuVtJRC",
  SUBSCRIPTION: process.env.NEXT_PUBLIC_GADS_SUBSCRIPTION_CONVERSION,
} as const;

export function trackConversion(sendTo?: string): void {
  if (typeof window === "undefined") return;
  if (!sendTo || sendTo.includes("REPLACE_")) return;
  if (process.env.NODE_ENV === "development") {
    console.log(`[GAds Conversion] ${sendTo}`);
    return;
  }
  if (typeof window.gtag !== "function") return;
  window.gtag("event", "conversion", { send_to: sendTo });
}

export const EVENTS = {
  LANDING_VIEW:         "landing_view",
  SIGNUP_STARTED:       "signup_started",
  SIGNUP_COMPLETED:     "signup_completed",
  ONBOARDING_STARTED:   "onboarding_started",
  ONBOARDING_STEP:      "onboarding_step",
  ONBOARDING_COMPLETED: "onboarding_completed",
  WORKOUT_CREATED:      "workout_created",
  WORKOUT_STARTED:      "workout_started",
  WORKOUT_COMPLETED:    "workout_completed",
  PAYWALL_VIEWED:       "paywall_viewed",
  CHECKOUT_STARTED:     "checkout_started",
  SUBSCRIPTION_CREATED: "subscription_created",
  AI_TIP_VIEWED:        "ai_tip_viewed",
  AI_WORKOUT_GENERATED: "ai_workout_generated",
  SCREEN_VIEW:          "screen_view",
  CTA_CLICK:            "cta_click",
  APP_PROMO_VIEWED:     "app_promo_viewed",
  APP_PROMO_CLICK:      "app_promo_click",
  APP_PROMO_DISMISSED:  "app_promo_dismissed",
} as const;

const PLAN_ANALYTICS: Record<BillingPlanName, {
  billing_cycle: "monthly" | "yearly";
  value: number;
}> = {
  pro_monthly: { billing_cycle: "monthly", value: 19.9 },
  pro_yearly:  { billing_cycle: "yearly",  value: 118.8 },
};

export function checkoutEventParams(
  plan: BillingPlanName,
  source: string
): EventParams {
  return {
    plan_name: plan,
    billing_cycle: PLAN_ANALYTICS[plan].billing_cycle,
    source,
    value: PLAN_ANALYTICS[plan].value,
  };
}

export function trackCheckoutStarted(plan: BillingPlanName, source: string): void {
  trackEvent(EVENTS.CHECKOUT_STARTED, checkoutEventParams(plan, source));
}

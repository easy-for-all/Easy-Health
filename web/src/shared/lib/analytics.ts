declare global {
  interface Window {
    gtag?: (...args: unknown[]) => void;
  }
}

type EventParams = Record<string, string | number | boolean | undefined>;

export function trackEvent(eventName: string, params?: EventParams): void {
  if (typeof window === "undefined") return;
  if (process.env.NODE_ENV === "development") {
    console.log(`[Analytics] ${eventName}`, params ?? {});
  }
  if (typeof window.gtag !== "function") return;
  window.gtag("event", eventName, params);
}

export const EVENTS = {
  LANDING_VIEW:         "landing_view",
  SIGNUP_STARTED:       "signup_started",
  SIGNUP_COMPLETED:     "signup_completed",
  ONBOARDING_STARTED:   "onboarding_started",
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
} as const;

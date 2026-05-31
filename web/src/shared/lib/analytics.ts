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

// send_to labels: get from Google Ads → Conversions → select action → Tag setup
export const CONVERSIONS = {
  SIGNUP:       "AW-17759537883/-FCPCJ7mkrAcENuVtJRC",
  SUBSCRIPTION: "AW-17759537883/REPLACE_SUBSCRIPTION_LABEL",
} as const;

export function trackConversion(sendTo: string): void {
  if (typeof window === "undefined") return;
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
} as const;

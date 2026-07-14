declare global {
  interface Window {
    gtag?: (...args: unknown[]) => void;
  }
}

type EventParams = Record<string, string | number | boolean | undefined>;
export type BillingPlanName = "pro_monthly" | "pro_yearly";

export function trackEvent(eventName: string, params?: EventParams): void {
  if (typeof window === "undefined") return;
  if (process.env.NODE_ENV === "development") {
    console.log(`[Analytics] ${eventName}`, params ?? {});
  }
  if (typeof window.gtag !== "function") return;
  window.gtag("event", eventName, params);
}

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

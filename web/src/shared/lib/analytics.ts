declare global {
  interface Window {
    gtag: (...args: unknown[]) => void;
  }
}

const GTAG_ID = "G-FG3BDM75T1";

function gtag(event: string, params?: Record<string, unknown>) {
  if (typeof window === "undefined" || typeof window.gtag !== "function") return;
  window.gtag("event", event, { send_to: GTAG_ID, ...params });
}

export const analytics = {
  signupStarted: () => gtag("signup_started"),
  signupCompleted: () => gtag("signup_completed"),

  onboardingStep: (step: number, label: string) =>
    gtag("onboarding_step", { step, label }),
  onboardingCompleted: () => gtag("onboarding_completed"),

  paywallViewed: (plan?: string) => gtag("paywall_viewed", { plan }),
  checkoutStarted: (plan: string) => gtag("checkout_started", { plan }),

  ctaClick: (location: string) => gtag("cta_click", { location }),
};

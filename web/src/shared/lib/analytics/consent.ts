// Google Consent Mode v2 (LGPD). Analytics/ads storage default to "denied";
// granted only after the visitor opts in. Call setDefaultConsent() BEFORE the
// gtag config runs so no cookie is written without consent.

type ConsentState = "granted" | "denied";
const CONSENT_KEY = "eh_consent";

function gtag(...args: unknown[]): void {
  if (typeof window === "undefined") return;
  const w = window as Window & { gtag?: (...a: unknown[]) => void };
  if (typeof w.gtag === "function") w.gtag(...args);
}

export function storedConsent(): ConsentState | null {
  try {
    const v = typeof window !== "undefined" ? window.localStorage.getItem(CONSENT_KEY) : null;
    return v === "granted" || v === "denied" ? v : null;
  } catch {
    return null;
  }
}

// Emitted into dataLayer even before gtag.js finishes loading.
export function setDefaultConsent(): void {
  const prior = storedConsent();
  const analytics: ConsentState = prior === "granted" ? "granted" : "denied";
  gtag("consent", "default", {
    ad_storage: analytics,
    ad_user_data: analytics,
    ad_personalization: analytics,
    analytics_storage: analytics,
    wait_for_update: 500,
  });
}

export function updateConsent(state: ConsentState): void {
  try {
    if (typeof window !== "undefined") window.localStorage.setItem(CONSENT_KEY, state);
  } catch {
    /* ignore */
  }
  gtag("consent", "update", {
    ad_storage: state,
    ad_user_data: state,
    ad_personalization: state,
    analytics_storage: state,
  });
}

export function hasDecidedConsent(): boolean {
  return storedConsent() !== null;
}

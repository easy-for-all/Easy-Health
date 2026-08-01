import { useEffect } from "react";
import * as Sentry from "@sentry/nextjs";
import { ApiError } from "@/shared/lib/api";
import { trackEvent, trackOnce } from "@/shared/lib/analytics";
import { getAnalyticsContext } from "@/shared/lib/analytics/context";

// Instrumentation for the stretch that used to be completely dark: from the
// moment an auth screen renders to the moment the request reaches the API.
// Before this, an install that opened and left was indistinguishable from one
// that tapped Google and failed on the device — the first server-side event of
// the whole flow (google_auth_started) only fires once the request lands.
//
// PRIVACY: every property here is an enum, a boolean or an HTTP status. Never a
// password, a token, an e-mail or a raw error message.

export type AuthScreen = "login" | "sign_up";
export type AuthOrigin = "landing" | "login" | "sign_up";
export type AuthProvider = "google" | "email";

type AuthProviderClick =
  | {
      provider: AuthProvider;
      authScreen: "sign_up";
      intent: "sign_up";
      termsAccepted: boolean;
    }
  | {
      provider: AuthProvider;
      authScreen: "login";
      intent: "login";
    };

// Where in the flow it broke. Closed vocabulary so a stray string can never
// become a new dimension value.
export type AuthStage =
  | "google_plugin"
  | "google_exchange"
  | "email_login"
  | "email_signup";

const MAX_CODE_LENGTH = 64;

function safeCode(value: unknown): string {
  const raw = typeof value === "string" ? value : "";
  const cleaned = raw.trim().replace(/[^A-Za-z0-9_.:-]/g, "_");
  return cleaned.length > 0 ? cleaned.slice(0, MAX_CODE_LENGTH) : "unknown";
}

/**
 * Fires once per screen per session, from an effect, so it means "the screen the
 * user can act on actually rendered" — not "a component was constructed".
 * trackOnce guards against React Strict Mode's double invoke and remounts.
 */
export function useAuthScreenView(screen: AuthScreen): void {
  useEffect(() => {
    trackOnce(`auth_screen_viewed:${screen}`, "auth_screen_viewed", {
      auth_screen: screen,
    });
  }, [screen]);
}

/** The user explicitly chose to create a new account. */
export function trackSignupSelected(from: AuthOrigin): void {
  trackEvent("signup_selected", { from });
}

/** The user explicitly chose to sign in to an existing account. */
export function trackLoginSelected(from: AuthOrigin): void {
  trackEvent("login_selected", { from });
}

/** The user clicked an auth provider/submit before any auth side effect begins. */
export function trackAuthProviderClicked(click: AuthProviderClick): void {
  trackEvent("auth_provider_clicked", {
    provider: click.provider,
    auth_screen: click.authScreen,
    intent: click.intent,
    source: "auth_screen",
    ...(click.authScreen === "sign_up" ? { terms_accepted: click.termsAccepted } : {}),
  });
}

/**
 * A real client-side failure during authentication: the native plugin refused,
 * the SDK never loaded, the picker returned nothing. Never used for a validation
 * message the user can simply fix.
 */
export function trackAuthClientError(
  stage: AuthStage,
  errorCode: unknown,
  provider?: string
): void {
  trackEvent("auth_client_error", {
    stage,
    error_code: safeCode(errorCode),
    ...(provider ? { provider } : {}),
  });
}

/**
 * The auth API answered with an error. `http_status` is what separates "we never
 * reached the server" (auth_client_error) from "the server said no", which is
 * the distinction the funnel could not make at all.
 */
export function trackAuthApiError(stage: AuthStage, error: unknown, provider?: string): void {
  const status = error instanceof ApiError ? error.status : 0;
  const code = error instanceof ApiError ? error.errorCode : undefined;

  trackEvent("auth_api_error", {
    stage,
    http_status: status,
    error_code: safeCode(code ?? (status === 0 ? "network" : String(status))),
    ...(provider ? { provider } : {}),
  });
}

/**
 * Sends an auth failure to Sentry with the dimensions needed to tell one build
 * and one installation apart. Deliberately no token, no e-mail, no password —
 * only the code and the context. Never throws.
 */
export function reportAuthError(
  stage: AuthStage,
  error: unknown,
  extra: Record<string, unknown> = {}
): void {
  try {
    const ctx = getAnalyticsContext();
    Sentry.captureException(error, {
      tags: {
        auth_stage: stage,
        platform: ctx.platform,
        app_version: ctx.app_version ?? "unknown",
        build_number: ctx.build_number ?? "unknown",
        route: typeof window !== "undefined" ? window.location.pathname : "unknown",
      },
      extra: { ...extra, installation_id: ctx.installation_id ?? null },
    });
  } catch {
    /* monitoring must never break authentication */
  }
}

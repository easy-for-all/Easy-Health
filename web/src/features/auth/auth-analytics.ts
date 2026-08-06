import { useEffect } from "react";
import * as Sentry from "@sentry/nextjs";
import { ApiError } from "@/shared/lib/api";
import { trackEvent, trackOnce } from "@/shared/lib/analytics";
import { getAnalyticsContext } from "@/shared/lib/analytics/context";
import type { AuthFailureCategory } from "@/shared/lib/googleAuth";

// Instrumentation for the stretch that used to be completely dark: from the
// moment an auth screen renders to the moment the request reaches the API.
// Before this, an install that opened and left was indistinguishable from one
// that tapped Google and failed on the device — the first server-side event of
// the whole flow (google_auth_started) only fires once the request lands.
//
// PRIVACY: every property here is an enum, a boolean or an HTTP status. Never a
// password, a token, an e-mail or a raw error message.

export type AuthScreen = "login" | "sign_up";
export type AuthOrigin = "landing" | "login" | "sign_up" | "native_entry";
export type AuthProvider = "google" | "email";
export type AuthIntent = "login" | "sign_up";

/**
 * Everything every event of ONE attempt must carry. `authAttemptId` is what
 * turns a scattered set of rows into a story: the tap, the failure and the retry
 * of the same person stop being indistinguishable from three different people.
 */
export interface AuthAttemptContext {
  authAttemptId: string;
  provider: AuthProvider;
  intent: AuthIntent;
  authScreen: AuthScreen;
}

function attemptParams(ctx: AuthAttemptContext) {
  return {
    auth_attempt_id: ctx.authAttemptId,
    provider: ctx.provider,
    intent: ctx.intent,
    auth_screen: ctx.authScreen,
  };
}

type AuthProviderClick =
  | (AuthAttemptContext & { authScreen: "sign_up"; intent: "sign_up"; termsAccepted: boolean })
  | (AuthAttemptContext & { authScreen: "login"; intent: "login" });

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
    ...attemptParams(click),
    source: "auth_screen",
    ...(click.authScreen === "sign_up" ? { terms_accepted: click.termsAccepted } : {}),
  });
}

/** The social provider flow began on the device. */
export function trackSocialLoginStarted(ctx: AuthAttemptContext): void {
  trackEvent("social_login_started", attemptParams(ctx));
}

/**
 * The terminal failure of a social attempt — including a deliberate
 * cancellation, which is a failure of the attempt but NOT a defect. It is
 * emitted exactly once per attempt, whether the flow died on the device or the
 * API answered with an error; the second event (auth_client_error /
 * auth_api_error) is what says which.
 */
export function trackSocialLoginFailed(
  ctx: AuthAttemptContext,
  failureCategory: AuthFailureCategory,
  errorCode: unknown
): void {
  trackEvent("social_login_failed", {
    ...attemptParams(ctx),
    failure_category: failureCategory,
    error_code: safeCode(errorCode),
  });
}

/**
 * The social attempt ended with a session. Fires once per attempt: a resume or a
 * rerender must never turn one successful login into two conversions.
 */
export function trackSocialLoginCompleted(ctx: AuthAttemptContext): void {
  trackOnce(`social_login_completed:${ctx.authAttemptId}`, "social_login_completed", attemptParams(ctx));
}

export function trackLoginStarted(ctx: AuthAttemptContext): void {
  trackEvent("login_started", { ...attemptParams(ctx), method: ctx.provider });
}

export function trackLoginCompleted(ctx: AuthAttemptContext): void {
  trackOnce(`login_completed:${ctx.authAttemptId}`, "login_completed", attemptParams(ctx));
}

export function trackSignupStarted(ctx: AuthAttemptContext): void {
  trackEvent("signup_started", { ...attemptParams(ctx), method: ctx.provider });
}

export function trackSignupCompleted(ctx: AuthAttemptContext): void {
  trackOnce(`signup_completed:${ctx.authAttemptId}`, "signup_completed", attemptParams(ctx));
}

/**
 * A real client-side failure during authentication: the native plugin refused,
 * the SDK never loaded, the picker returned nothing. Never used for a validation
 * message the user can simply fix, and NEVER for a cancellation — the user
 * choosing to back out is not a client error.
 */
export function trackAuthClientError(
  stage: AuthStage,
  errorCode: unknown,
  ctx?: AuthAttemptContext,
  failureCategory?: AuthFailureCategory | EmailFailureCategory
): void {
  trackEvent("auth_client_error", {
    stage,
    error_code: safeCode(errorCode),
    ...(ctx ? attemptParams(ctx) : {}),
    ...(failureCategory ? { failure_category: failureCategory } : {}),
  });
}

/**
 * The auth API answered with an error. `http_status` is what separates "we never
 * reached the server" (auth_client_error) from "the server said no", which is
 * the distinction the funnel could not make at all.
 */
export function trackAuthApiError(
  stage: AuthStage,
  error: unknown,
  ctx?: AuthAttemptContext,
  failureCategory?: AuthFailureCategory | EmailFailureCategory
): void {
  const status = error instanceof ApiError ? error.status : 0;
  const code = error instanceof ApiError ? error.errorCode : undefined;

  trackEvent("auth_api_error", {
    stage,
    http_status: status,
    error_code: safeCode(code ?? (status === 0 ? "network" : String(status))),
    ...(ctx ? attemptParams(ctx) : {}),
    ...(failureCategory ? { failure_category: failureCategory } : {}),
  });
}

// Closed vocabulary for the e-mail flows, derived from the HTTP status rather
// than from the server's message: the message is user-facing copy that changes,
// the status is the contract.
export type EmailFailureCategory =
  | "invalid_credentials"
  | "validation_error"
  | "rate_limited"
  | "network_error"
  | "backend_error"
  | "unknown";

export function emailFailureCategory(error: unknown): EmailFailureCategory {
  if (error instanceof TypeError) return "network_error";
  if (!(error instanceof ApiError)) return "unknown";

  if (error.status === 401) return "invalid_credentials";
  if (error.status === 422 || error.status === 400) return "validation_error";
  if (error.status === 429) return "rate_limited";
  if (error.status >= 500) return "backend_error";
  if (error.status === 0) return "network_error";
  return "unknown";
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

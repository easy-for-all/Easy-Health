import * as Sentry from "@sentry/nextjs";
import { api } from "@/shared/lib/api";
import { detectPlatform } from "@/shared/lib/analytics/context";
import { ensureInstallationForAuth } from "@/shared/lib/analytics/installation";
import type { User } from "@/shared/types/user";

// Web (browser) Google login still goes through the server-side OmniAuth flow.
// Android uses the native Google Sign-In below instead.
const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";
export const GOOGLE_AUTH_WEB_URL = `${API_URL}/auth/google/web`;

const WEB_CLIENT_ID = process.env.NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID ?? "";

export interface GoogleNativeUser extends User {
  new_user?: boolean;
}

// Consent carried into the social sign-up flows. Only sent from the sign-up
// screen (after its consent gate); the login screen omits it, so the backend
// refuses to CREATE a new account there but still lets existing users in.
// The backend is the authority: we never guess whether an account exists.
export interface GoogleConsent {
  termsAccepted: boolean;
  privacyAccepted: boolean;
  marketingConsent?: boolean;
}

/**
 * Builds the server-side OmniAuth URL, forwarding consent as query params so it
 * survives the OAuth redirect round-trip (read back from `omniauth.params`).
 *
 * `platform` is always sent, consent or not: the OAuth callback is a browser
 * navigation coming back from Google and therefore carries no X-Platform header,
 * so this query param is the ONLY channel by which the signup origin reaches the
 * server on this flow. Same robust detection used for every X-Platform header.
 */
export function googleAuthWebUrl(consent?: GoogleConsent): string {
  const params = new URLSearchParams({ platform: detectPlatform() });
  if (consent) {
    params.set("terms_accepted", consent.termsAccepted ? "1" : "0");
    params.set("privacy_accepted", consent.privacyAccepted ? "1" : "0");
    params.set("marketing_consent", consent.marketingConsent ? "1" : "0");
  }
  return `${GOOGLE_AUTH_WEB_URL}?${params.toString()}`;
}

export class GoogleAuthError extends Error {
  code: string;

  constructor(message: string, code = "google_native_failed") {
    super(message);
    this.name = "GoogleAuthError";
    this.code = code;
  }
}

/**
 * Structured diagnostic logger for the Google auth flow. Visible in the Android
 * WebView console via chrome://inspect. Never logs the token itself — only its
 * presence/length — so the trail is safe to keep on.
 */
export function authLog(step: string, data?: Record<string, unknown>) {
  const payload = { t: new Date().toISOString(), ...data };
  console.log(`[GoogleAuth] ${step}`, payload);
  // A console line only exists while a debugger is attached, which is never the
  // case on a real user's phone. The breadcrumb is what turns a captured auth
  // failure into a readable trail of the steps that led to it.
  try {
    Sentry.addBreadcrumb({
      category: "google_auth",
      level: step.includes("error") || step.includes("failed") ? "warning" : "info",
      message: step,
      data: payload,
    });
  } catch {
    /* Sentry not initialized — diagnostics must never throw */
  }
}

/**
 * Safely extracts everything useful from an unknown thrown value without ever
 * touching sensitive fields (idToken/accessToken/clientId/email are never read).
 * Used so a plugin rejection is never flattened into an opaque code again.
 */
export function serializeAuthError(err: unknown): Record<string, unknown> {
  if (err === null || (typeof err !== "object" && !(err instanceof Error))) {
    return { value: String(err) };
  }

  const obj = err as Record<string, unknown>;
  const cause = obj?.cause;

  return {
    type: typeof err,
    constructorName: (err as { constructor?: { name?: string } })?.constructor?.name,
    name: obj?.name,
    message: obj?.message,
    code: obj?.code,
    stack: obj?.stack,
    cause: cause == null ? undefined : typeof cause === "string" ? cause : String(cause),
    keys: Object.keys(obj ?? {}),
    ownPropertyNames: Object.getOwnPropertyNames(err),
  };
}

let initialized = false;

async function ensureInitialized() {
  if (initialized) return;
  if (!WEB_CLIENT_ID) {
    throw new GoogleAuthError(
      "NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID ausente no build",
      "missing_web_client_id",
    );
  }

  let SocialLogin;
  try {
    ({ SocialLogin } = await import("@capgo/capacitor-social-login"));
  } catch (err) {
    authLog("plugin_import_error", {
      name: (err as Error)?.name,
      message: (err as Error)?.message,
    });
    throw new GoogleAuthError(
      (err as Error)?.message ?? "Falha ao carregar o plugin de login",
      "plugin_import_failed",
    );
  }

  try {
    await SocialLogin.initialize({ google: { webClientId: WEB_CLIENT_ID } });
  } catch (err) {
    authLog("plugin_init_error", {
      name: (err as Error)?.name,
      message: (err as Error)?.message,
    });
    throw new GoogleAuthError(
      (err as Error)?.message ?? "Falha ao inicializar o plugin de login",
      "plugin_init_failed",
    );
  }

  initialized = true;
  authLog("plugin_initialized");
}

/**
 * Opens the native Android account picker (the only screen Google requires) and
 * returns the Google ID token. Throws GoogleAuthError with the plugin error code
 * so the caller can surface it for diagnosis.
 */
export async function nativeGoogleSignIn(): Promise<string> {
  authLog("sign_in_start");
  await ensureInitialized();

  const { SocialLogin } = await import("@capgo/capacitor-social-login");
  let result;
  try {
    // Do NOT pass custom `scopes` here: the native plugin rejects any custom
    // scope array unless MainActivity implements ModifiedMainActivityForSocialLoginPlugin,
    // and that reject carries no code so it surfaced as the opaque "plugin_login_failed".
    // The base email/profile/openid scopes are always added by the plugin, and the
    // id_token (all we need) does not depend on extra scopes.
    ({ result } = await SocialLogin.login({
      provider: "google",
      options: {},
    }));
  } catch (err) {
    // Preserve the real plugin code when present; only fall back to the generic
    // code when none is available. Full safe diagnostics go to the console.
    const details = serializeAuthError(err);
    const rawCode = details.code;
    const code = typeof rawCode === "string" && rawCode.length > 0 ? rawCode : "plugin_login_failed";
    authLog("sign_in_plugin_error", details);
    throw new GoogleAuthError(
      typeof details.message === "string" ? details.message : "Falha no login Google",
      code,
    );
  }

  const idToken = "idToken" in result ? result.idToken : null;
  authLog("sign_in_result", { hasIdToken: Boolean(idToken), tokenLength: idToken?.length ?? 0 });

  if (!idToken) {
    throw new GoogleAuthError("Google não retornou o token de identidade", "missing_id_token");
  }
  return idToken;
}

export async function postGoogleNative(idToken: string, consent?: GoogleConsent) {
  authLog("exchange_start");
  // Boot registers the installation fire-and-forget, so on a fast login the id
  // may not be cached yet and api.post would omit X-Installation-Id. Resolving it
  // here lets the backend link the installation in this very sign_in cycle.
  // Time-boxed and best-effort: a failure only defers the link to the next
  // authenticated request, and is left as a Sentry breadcrumb rather than swallowed.
  const installation = await ensureInstallationForAuth();
  if (!installation.installationId) {
    authLog("installation_unavailable", { failureCode: installation.failureCode });
  }
  try {
    const user = await api.post<GoogleNativeUser>("/api/v1/auth/google/native", {
      id_token: idToken,
      platform: "android",
      ...(consent
        ? {
            terms_accepted: consent.termsAccepted,
            privacy_accepted: consent.privacyAccepted,
            marketing_consent: consent.marketingConsent ?? false,
          }
        : {}),
    });
    const redirectPath = user.new_user ? "/onboarding" : "/dashboard";
    authLog("exchange_success", { userId: user.id, newUser: user.new_user, redirectPath });
    return { user, redirectPath };
  } catch (err) {
    const code = (err as { errorCode?: string })?.errorCode ?? "exchange_failed";
    authLog("exchange_error", { code, message: (err as Error)?.message });
    throw new GoogleAuthError((err as Error)?.message ?? "Falha ao autenticar", code);
  }
}

/**
 * Single entry point for both auth screens. Keeps the native-vs-web decision and
 * the web navigation in one place so neither screen depends on an `<a href>`
 * being present in the server-rendered HTML — a link that used to be followed by
 * taps landing before hydration, sending the Android WebView into the browser
 * OAuth flow that Google rejects with `disallowed_useragent`.
 *
 * `consent` is only ever passed by the sign-up screen, after its own gate.
 */
export type GoogleAuthOutcome =
  | { navigated: true }
  | { navigated: false; redirectPath: string };

export async function startGoogleAuth(
  { native, consent }: { native: boolean; consent?: GoogleConsent },
): Promise<GoogleAuthOutcome> {
  if (!native) {
    // Browsers keep the server-side OmniAuth flow. Navigating explicitly (rather
    // than relying on a link) means the consent query params can never be lost.
    window.location.assign(googleAuthWebUrl(consent));
    return { navigated: true };
  }

  const idToken = await nativeGoogleSignIn();
  const { redirectPath } = await postGoogleNative(idToken, consent);
  return { navigated: false, redirectPath };
}

// What actually went wrong, so each screen can respond instead of collapsing
// every outcome into "Não foi possível entrar".
// - consent_required: this Google account does not exist yet → send to sign-up.
// - cancelled:        the user dismissed the account picker → not an error.
export type GoogleAuthFailure =
  | "consent_required"
  | "cancelled"
  | "account_deleted"
  | "invalid_token"
  | "network"
  | "unknown";

// The analytics dimension, kept apart from GoogleAuthFailure on purpose: the
// vocabulary above routes the UI (which banner, which CTA), this one answers
// "what kind of thing went wrong" for the funnel and the Admin.
export type AuthFailureCategory =
  | "user_cancelled"
  | "provider_error"
  | "oauth_configuration_error"
  | "network_error"
  | "timeout"
  | "backend_error"
  | "unknown";

// A voluntary cancellation is recognised by EXPLICIT CODES ONLY.
//
// It used to be inferred from /cancel/i over the code AND the message, which
// meant any plugin error whose message happened to contain "cancel" — a
// cancelled request, a cancelled coroutine — was filed as a user decision and
// silently dropped from the failure counters.
//
// The contract is documented by the plugin itself: GoogleProvider.java rejects
// GetCredentialCancellationException with USER_CANCELLED, and definitions.d.ts
// declares `SocialLoginErrorCode = 'USER_CANCELLED'`. "cancelled" is kept
// because the plugin's own JS layer mints it on some web/provider paths.
const CANCELLED_CODES = ["USER_CANCELLED", "cancelled"];

// The single normalized code we report for a cancellation, whatever spelling
// the plugin used, so the Admin has one value to match on.
export const USER_CANCELLED_CODE = "USER_CANCELLED";

function isCancelledCode(code: string): boolean {
  return CANCELLED_CODES.some((known) => known.toLowerCase() === code.toLowerCase());
}

// Codes that mean the request never left the device.
const CONFIGURATION_CODES = ["missing_web_client_id", "plugin_init_failed"];
const PROVIDER_CODES = ["plugin_import_failed", "plugin_login_failed", "missing_id_token"];
// Codes the BACKEND produced. oauth_failed belongs here: it is the error_code
// the API returns from its own rescue, so filing it as a plugin failure blamed
// the device for something the server said.
const BACKEND_CODES = ["consent_required", "account_deleted", "invalid_token", "invalid_audience", "oauth_failed"];

export interface GoogleAuthErrorInfo {
  /** Drives the UI. Unchanged vocabulary. */
  failure: GoogleAuthFailure;
  /** Drives analytics. Closed vocabulary, never a message. */
  category: AuthFailureCategory;
  /** Normalized, safe to send as a dimension. */
  errorCode: string;
  /** true when the API answered (or was reached); false when it broke on the device. */
  reachedBackend: boolean;
}

/**
 * The one place that decides what a Google auth rejection means. Reads the code
 * only — never the message, which is human text from a third-party SDK and must
 * never become a dimension value or a branch condition.
 */
export function describeGoogleAuthError(err: unknown): GoogleAuthErrorInfo {
  const code = err instanceof GoogleAuthError ? err.code : "";

  if (isCancelledCode(code)) {
    return {
      failure: "cancelled",
      category: "user_cancelled",
      errorCode: USER_CANCELLED_CODE,
      reachedBackend: false,
    };
  }

  if (BACKEND_CODES.includes(code)) {
    const failure: GoogleAuthFailure =
      code === "consent_required" ? "consent_required"
      : code === "account_deleted" ? "account_deleted"
      : code === "oauth_failed" ? "unknown"
      : "invalid_token";

    return { failure, category: "backend_error", errorCode: code, reachedBackend: true };
  }

  if (CONFIGURATION_CODES.includes(code)) {
    return { failure: "unknown", category: "oauth_configuration_error", errorCode: code, reachedBackend: false };
  }

  if (PROVIDER_CODES.includes(code)) {
    return { failure: "unknown", category: "provider_error", errorCode: code, reachedBackend: false };
  }

  const name = (err as Error)?.name;
  if (name === "TimeoutError" || name === "AbortError") {
    return { failure: "network", category: "timeout", errorCode: code || "timeout", reachedBackend: true };
  }

  // exchange_failed is the fallback code of postGoogleNative: the request left
  // the device and never came back with a structured answer.
  if (code === "exchange_failed" || err instanceof TypeError) {
    return { failure: "network", category: "network_error", errorCode: code || "network", reachedBackend: true };
  }

  return { failure: "unknown", category: "unknown", errorCode: code || "unknown", reachedBackend: false };
}

/** Kept for the screens and tests that only need the UI vocabulary. */
export function classifyGoogleAuthError(err: unknown): GoogleAuthFailure {
  return describeGoogleAuthError(err).failure;
}

import { api } from "@/shared/lib/api";
import type { User } from "@/shared/types/user";

// Web (browser) Google login still goes through the server-side OmniAuth flow.
// Android uses the native Google Sign-In below instead.
const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";
export const GOOGLE_AUTH_WEB_URL = `${API_URL}/auth/google/web`;

const WEB_CLIENT_ID = process.env.NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID ?? "";

export interface GoogleNativeUser extends User {
  new_user?: boolean;
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

export async function postGoogleNative(idToken: string) {
  authLog("exchange_start");
  try {
    const user = await api.post<GoogleNativeUser>("/api/v1/auth/google/native", {
      id_token: idToken,
      platform: "android",
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

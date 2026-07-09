import { api } from "@/shared/lib/api";
import type { User } from "@/shared/types/user";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";
const MOBILE_AUTH_PATH = "/mobile-auth/callback";
const OFFICIAL_HOST = "easyhealth.art";

export const GOOGLE_AUTH_WEB_URL = `${API_URL}/auth/google/web`;
export const GOOGLE_AUTH_ANDROID_URL = `${API_URL}/auth/google/android`;

export type MobileAuthPlatform = "android" | "ios";

export interface MobileAuthUser extends User {
  new_user?: boolean;
}

export type ParsedMobileAuthCallback =
  | { type: "code"; code: string; platform: MobileAuthPlatform; url: URL }
  | { type: "error"; error: string; platform: MobileAuthPlatform; url: URL }
  | { type: "legacy-token"; token: string; platform: MobileAuthPlatform; url: URL };

export class MobileAuthError extends Error {
  code: string;

  constructor(message: string, code = "oauth_failed") {
    super(message);
    this.name = "MobileAuthError";
    this.code = code;
  }
}

export function parseMobileAuthCallback(rawUrl: string): ParsedMobileAuthCallback | null {
  let url: URL;

  try {
    url = new URL(rawUrl);
  } catch {
    return null;
  }

  if (!isSupportedCallbackUrl(url)) return null;

  const platform = normalizePlatform(url.searchParams.get("platform"));
  const error = url.searchParams.get("error");
  if (error) return { type: "error", error, platform, url };

  const code = url.searchParams.get("code");
  if (code) return { type: "code", code, platform, url };

  const token = url.searchParams.get("token");
  if (token && isLegacyCallbackUrl(url)) return { type: "legacy-token", token, platform, url };

  return { type: "error", error: "missing_code", platform, url };
}

export async function exchangeMobileAuthCallback(parsed: ParsedMobileAuthCallback) {
  if (parsed.type === "error") {
    throw new MobileAuthError("Não conseguimos concluir o login. Tente novamente.", parsed.error);
  }

  if (parsed.type === "legacy-token") {
    throw new MobileAuthError("Atualize o app e tente entrar novamente.", "legacy_mobile_callback");
  }

  const user = await api.post<MobileAuthUser>("/api/v1/auth/mobile/exchange", {
    code: parsed.code,
    platform: parsed.platform,
  });

  return {
    user,
    redirectPath: user.new_user ? "/onboarding" : "/dashboard",
  };
}

export function buildCustomSchemeCallbackUrl(parsed: ParsedMobileAuthCallback) {
  const params = new URLSearchParams();
  params.set("platform", parsed.platform);

  if (parsed.type === "code") params.set("code", parsed.code);
  if (parsed.type === "error") params.set("error", parsed.error);

  return `easyhealth://auth/callback?${params.toString()}`;
}

export function removeSensitiveMobileAuthParams() {
  if (typeof window === "undefined") return;
  window.history.replaceState({}, document.title, MOBILE_AUTH_PATH);
}

function isSupportedCallbackUrl(url: URL) {
  return isHttpsAppLinkCallback(url) || isCustomSchemeCallback(url) || isLegacyCallbackUrl(url);
}

function isHttpsAppLinkCallback(url: URL) {
  return url.protocol === "https:" && url.hostname === OFFICIAL_HOST && url.pathname === MOBILE_AUTH_PATH;
}

function isCustomSchemeCallback(url: URL) {
  return url.protocol === "easyhealth:" && url.hostname === "auth" && url.pathname === "/callback";
}

function isLegacyCallbackUrl(url: URL) {
  return url.protocol === "easyhealth:" && url.hostname === "auth-callback";
}

function normalizePlatform(platform: string | null): MobileAuthPlatform {
  return platform === "ios" ? "ios" : "android";
}

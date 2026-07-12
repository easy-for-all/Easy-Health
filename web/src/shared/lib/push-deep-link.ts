// Safe resolution of the route a push should open. NEVER trust the raw path from
// the notification payload — validate it against an allowlist to prevent open
// redirects / navigation to arbitrary URLs inside the WebView.

const ALLOWED_PREFIXES = ["/workouts", "/workout", "/plan"];
export const DEEP_LINK_FALLBACK = "/workouts/ready";

export function isSafeInternalPath(path: unknown): path is string {
  if (typeof path !== "string" || path.length === 0) return false;
  if (!path.startsWith("/")) return false;      // must be an app-relative path
  if (path.startsWith("//")) return false;      // protocol-relative URL
  if (path.includes("://")) return false;       // absolute URL with scheme
  if (/[\n\r\t\\]/.test(path)) return false;     // control chars / backslashes
  return true;
}

export function resolveDeepLink(data: Record<string, unknown> | null | undefined): string {
  const path = data?.target_path;
  if (
    isSafeInternalPath(path) &&
    ALLOWED_PREFIXES.some((prefix) => path === prefix || path.startsWith(`${prefix}/`))
  ) {
    return path;
  }
  return DEEP_LINK_FALLBACK;
}

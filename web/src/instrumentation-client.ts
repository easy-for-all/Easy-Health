// Client-side Sentry init (Next.js 16 instrumentation-client convention).
// Runs before the app becomes interactive. No-op unless NEXT_PUBLIC_SENTRY_DSN
// is set, so local/dev without a DSN is unaffected. Errors here never bubble.
import * as Sentry from "@sentry/nextjs";
import { getAnalyticsContext } from "@/shared/lib/analytics/context";
import { safeLocal, safeSession } from "@/shared/lib/safe-storage";

const DSN = process.env.NEXT_PUBLIC_SENTRY_DSN;

try {
  if (DSN) {
    const ctx = getAnalyticsContext();
    Sentry.init({
      dsn: DSN,
      environment: ctx.environment,
      release: ctx.app_version || undefined,
      // Keep it lean: errors only, no performance/session-replay by default.
      tracesSampleRate: 0,
      // Never capture PII (LGPD). IPs/cookies are not sent.
      sendDefaultPii: false,
    });
    Sentry.setTags({
      platform: ctx.platform,
      app_surface: ctx.app_surface,
      app_version: ctx.app_version ?? "unknown",
      // Blocked storage is a real segment of production traffic (it is what
      // white-screened the landing in RUBY-RAILS-K), and it is invisible unless
      // tagged. Reported per store: browsers block them independently, and an
      // "unknown" app_version above is usually this. Nothing before these tags
      // touches storage outside a try/catch.
      local_storage_available: safeLocal.isAvailable() ? "yes" : "no",
      session_storage_available: safeSession.isAvailable() ? "yes" : "no",
    });
  }
} catch {
  // Monitoring setup must never break the app.
}

// Sentry captures navigation errors when this hook is exported.
export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;

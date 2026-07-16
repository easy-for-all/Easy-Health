// Client-side Sentry init (Next.js 16 instrumentation-client convention).
// Runs before the app becomes interactive. No-op unless NEXT_PUBLIC_SENTRY_DSN
// is set, so local/dev without a DSN is unaffected. Errors here never bubble.
import * as Sentry from "@sentry/nextjs";
import { getAnalyticsContext } from "@/shared/lib/analytics/context";

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
    });
  }
} catch {
  // Monitoring setup must never break the app.
}

// Sentry captures navigation errors when this hook is exported.
export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;

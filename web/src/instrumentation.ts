// Server-side Sentry init (Next.js instrumentation hook). No-op unless
// SENTRY_DSN (server) or NEXT_PUBLIC_SENTRY_DSN is set. Only the Node.js runtime
// is instrumented; the edge runtime is skipped to keep things lean.
import * as Sentry from "@sentry/nextjs";

export async function register() {
  const dsn = process.env.SENTRY_DSN || process.env.NEXT_PUBLIC_SENTRY_DSN;
  if (!dsn) return;
  if (process.env.NEXT_RUNTIME !== "nodejs") return;

  Sentry.init({
    dsn,
    environment: process.env.NEXT_PUBLIC_APP_ENV || process.env.NODE_ENV,
    tracesSampleRate: 0,
    sendDefaultPii: false,
  });
}

export const onRequestError = Sentry.captureRequestError;

import { Capacitor } from "@capacitor/core";
import * as Sentry from "@sentry/nextjs";
import { detectPlatform, getAnalyticsContext } from "./context";
import { flushOnBackground } from "./server";
import { initAnalyticsLifecycle } from "./lifecycle";
import { ensureInstallationRegistered, getInstallationId } from "./installation";
import { initFirebase } from "./firebase";
import { storedConsent } from "./consent";
import { trackOnce } from "./index";

// Single entry point, called once from the client on app boot. The Consent Mode
// default is set inline in the document head (before gtag config); here we wire
// lifecycle, the web session marker and the background flush.

let started = false;

// installation_id goes on the SCOPE, not on a tag: tags are indexed and searched
// externally, and this id belongs to the device. It is enough to correlate a
// crash with a row in app_installations when we already have the id in hand.
function applySentryContext(): void {
  try {
    const ctx = getAnalyticsContext();
    Sentry.setTags({
      platform: ctx.platform,
      app_surface: ctx.app_surface,
      app_version: ctx.app_version ?? "unknown",
      build_number: ctx.build_number ?? "unknown",
    });
    Sentry.setContext("installation", {
      installation_id: ctx.installation_id ?? null,
      session_id: ctx.session_id,
    });
  } catch {
    /* monitoring must never break the boot */
  }
}

export function initAnalytics(): void {
  if (started || typeof window === "undefined") return;
  started = true;

  if (Capacitor.isNativePlatform()) {
    void (async () => {
      // Resolve the installation_id BEFORE the first lifecycle event. It is a
      // local storage read (already time-boxed inside getInstallationId), but it
      // is async — so on a first-ever cold start app_first_open/app_opened used
      // to be emitted before the id existed and shipped without it, which is
      // exactly the install we most need to correlate. A failure here must not
      // stop the lifecycle: the events still go out, just without the id.
      try {
        await getInstallationId();
      } catch {
        /* no installation id — analytics continues degraded, never blocked */
      }
      await initAnalyticsLifecycle();
      // instrumentation-client.ts tags Sentry at init, when app_version and
      // build_number have not been read from the native App plugin yet — on a
      // first-ever boot they are simply undefined there. Re-tagging here is what
      // makes a crash attributable to a build and an installation.
      applySentryContext();
      // Register the installation (upsert) so the backend/admin panel can count
      // this real Android install — anonymously now, associated after login.
      // App boot is a genuine native session start, so stamp last_session_at.
      void ensureInstallationRegistered({}, { sessionStarted: true });
    })();
    // Native Firebase (Analytics/Crashlytics) — no-op unless flags are on.
    void initFirebase(storedConsent() === "granted");
  } else {
    // Web/PWA session start (idempotent per tab session).
    trackOnce("web_session_started", "web_session_started", {
      platform: detectPlatform(),
    });
  }

  // Flush queued auditable events when the tab is hidden/closed.
  window.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") flushOnBackground();
  });
  window.addEventListener("pagehide", flushOnBackground);
}

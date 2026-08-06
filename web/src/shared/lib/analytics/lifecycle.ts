import { Capacitor } from "@capacitor/core";
import {
  markInstalledOnce,
  readAndStoreAppVersion,
  setAppVersion,
  startAnalyticsSession,
} from "./context";
import { trackEvent, trackServerEvent } from "./index";
import { ensureInstallationRegistered } from "./installation";
import { flushOnBackground } from "./server";
import {
  backgroundDurationMs,
  clearBackground,
  markBackgrounded,
  shouldStartNewSession,
} from "./session";

// Native app lifecycle instrumentation via @capacitor/app. WebView-only: the
// app is a Capacitor shell around the remote site, so there is no native SDK —
// lifecycle is observed here. Idempotent and non-blocking: nothing here may
// delay or break the boot.

let initialized = false;

export async function initAnalyticsLifecycle(): Promise<void> {
  if (initialized) return;
  initialized = true;

  if (typeof window === "undefined") return;
  if (!Capacitor.isNativePlatform()) return; // web lifecycle handled elsewhere

  try {
    const { App } = await import("@capacitor/app");

    // A cold start opens a fresh session, and it must be opened BEFORE the first
    // event is emitted. getSessionId() mints an id on read, so emitting
    // app_first_open/app_opened first made them carry an id that
    // startAnalyticsSession() then discarded — the two different session_ids
    // observed in a single cold start in production. buildEvent snapshots the
    // context at enqueue time (server.ts), so those events stayed frozen on the
    // dead id instead of picking up the real one at flush.
    startAnalyticsSession();

    // Version/build + first_open / app_updated detection.
    try {
      const info = await App.getInfo();
      setAppVersion(info.version, info.build);
      const { previousVersion } = readAndStoreAppVersion(info.version, info.build);

      if (markInstalledOnce()) {
        trackEvent("app_first_open", { app_version: info.version });
      } else if (previousVersion && previousVersion !== info.version) {
        trackEvent("app_updated", {
          from_version: previousVersion,
          to_version: info.version,
        });
      }
      trackEvent("app_opened", { app_version: info.version });
    } catch {
      /* getInfo unavailable — still register listeners below */
      trackEvent("app_opened");
    }

    // The session itself was opened above, before the first event.
    trackEvent("session_started", { reason: "cold_start" });

    // Foreground/background transitions. Guard against duplicate resume events.
    // A resume only starts a NEW session after SESSION_TIMEOUT_MINUTES in the
    // background; a quick return keeps the same session.
    let wasActive = true;
    App.addListener("appStateChange", ({ isActive }) => {
      if (isActive && !wasActive) {
        const bgMs = backgroundDurationMs() ?? 0;
        if (shouldStartNewSession(bgMs)) {
          startAnalyticsSession();
          trackEvent("session_started", { reason: "resume_timeout" });
        }
        trackEvent("app_resumed", { background_seconds: Math.round(bgMs / 1000) });
        clearBackground();
        // Self-heal: a register that failed at boot gets another chance here.
        // No-op once it has succeeded in this app cycle, and single-flight, so
        // repeated resumes cannot turn into a request storm. Never awaited —
        // the resume path must stay instant.
        void ensureInstallationRegistered();
      } else if (!isActive && wasActive) {
        markBackgrounded();
        trackEvent("app_backgrounded");
        // The queue is debounced by 3s, so leaving the app used to be able to
        // take the last events of a session with it — including the auth failure
        // that made the person leave. This is the same beacon-based flush the web
        // build already runs on visibilitychange/pagehide; it is not a second
        // queue and it is never awaited, so it cannot delay the transition.
        try {
          flushOnBackground();
        } catch {
          /* best effort: a failed flush must not break the lifecycle listener */
        }
      }
      wasActive = isActive;
    });

    // Deep links (push taps / external intents route through here).
    App.addListener("appUrlOpen", ({ url }) => {
      trackServerEvent("deep_link_opened", { url_path: safePath(url) });
    });
  } catch {
    /* @capacitor/app not present — no-op */
  }
}

// Never log the full URL (may carry tokens); keep only the path.
function safePath(url: string): string {
  try {
    return new URL(url).pathname;
  } catch {
    return "";
  }
}

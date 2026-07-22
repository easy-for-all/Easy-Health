import { Capacitor } from "@capacitor/core";
import {
  markInstalledOnce,
  readAndStoreAppVersion,
  setAppVersion,
  startAnalyticsSession,
} from "./context";
import { trackEvent, trackServerEvent } from "./index";
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

    // Cold start always opens a fresh session.
    startAnalyticsSession();
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
      } else if (!isActive && wasActive) {
        markBackgrounded();
        trackEvent("app_backgrounded");
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

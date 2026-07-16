import { Capacitor } from "@capacitor/core";
import { detectPlatform } from "./context";
import { flushOnBackground } from "./server";
import { initAnalyticsLifecycle } from "./lifecycle";
import { trackOnce } from "./index";

// Single entry point, called once from the client on app boot. The Consent Mode
// default is set inline in the document head (before gtag config); here we wire
// lifecycle, the web session marker and the background flush.

let started = false;

export function initAnalytics(): void {
  if (started || typeof window === "undefined") return;
  started = true;

  if (Capacitor.isNativePlatform()) {
    void initAnalyticsLifecycle();
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

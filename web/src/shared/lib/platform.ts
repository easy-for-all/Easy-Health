import { useSyncExternalStore } from "react";
import { Capacitor } from "@capacitor/core";

// Direct link to the Android app on the Play Store. The default covers
// production; override with NEXT_PUBLIC_PLAY_STORE_URL if the listing moves.
export const PLAY_STORE_URL =
  process.env.NEXT_PUBLIC_PLAY_STORE_URL ??
  "https://play.google.com/store/apps/details?id=com.EasyHealth.myapp";

// Where (and whether) to promote the Android app for the current visitor.
// - "hidden":          inside the native app, on iOS web, or during SSR.
// - "android-button":  Android browser → direct Play Store button.
// - "desktop-qr":      desktop browser → QR code to scan with an Android phone.
export type AppPromoTarget = "hidden" | "android-button" | "desktop-qr";

// Source of truth for "is this the native app?" is Capacitor.isNativePlatform();
// userAgent is only used as a visual tie-breaker (Android vs desktop).
export function getAppPromoTarget(): AppPromoTarget {
  if (typeof window === "undefined") return "hidden";
  if (Capacitor.isNativePlatform()) return "hidden"; // already using the app
  const ua = navigator.userAgent || "";
  if (/Android/i.test(ua)) return "android-button";
  if (/iPhone|iPad|iPod/i.test(ua)) return "hidden"; // app is Android-only
  return "desktop-qr";
}

// SSR-safe: the server snapshot is always "hidden", so hydration matches; React
// swaps in the resolved client value right after mount. useSyncExternalStore is
// the idiomatic way to read a client-only value without setState-in-effect. The
// value never changes after mount, so subscribe is a no-op.
const noopSubscribe = () => () => {};

export function useAppPromoTarget(): AppPromoTarget {
  return useSyncExternalStore(noopSubscribe, getAppPromoTarget, () => "hidden");
}

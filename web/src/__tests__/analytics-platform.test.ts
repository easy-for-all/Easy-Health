import { describe, it, expect, beforeEach, vi } from "vitest";

// Platform classification is the root of the "Android counted as web" bug
// (docs/android-tracking-audit.md). These tests pin the hardened detection so a
// regression cannot silently reclassify Android.

async function detectWith(cap: { getPlatform: () => string; isNativePlatform: () => boolean }) {
  vi.resetModules();
  vi.doMock("@capacitor/core", () => ({ Capacitor: cap }));
  const ctx = await import("@/shared/lib/analytics/context");
  return ctx;
}

describe("detectPlatform (hardened)", () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
    window.localStorage.clear();
  });

  it("classifies a native Android shell as 'android'", async () => {
    const { detectPlatform, detectAppSurface, isNativeApp } = await detectWith({
      getPlatform: () => "android",
      isNativePlatform: () => true,
    });
    expect(detectPlatform()).toBe("android");
    expect(detectAppSurface()).toBe("native_shell");
    expect(isNativeApp()).toBe(true);
  });

  it("still classifies as 'android' when the bridge asserts native but getPlatform lies ('web')", async () => {
    // The exact failure mode behind the remote-WebView misclassification.
    const { detectPlatform } = await detectWith({
      getPlatform: () => "web",
      isNativePlatform: () => true,
    });
    expect(detectPlatform()).toBe("android");
  });

  it("classifies iOS native as 'unknown' (never 'web') — iOS app not shipped", async () => {
    const { detectPlatform } = await detectWith({
      getPlatform: () => "ios",
      isNativePlatform: () => true,
    });
    expect(detectPlatform()).toBe("unknown");
  });

  it("classifies a plain browser as 'web'", async () => {
    const { detectPlatform } = await detectWith({
      getPlatform: () => "web",
      isNativePlatform: () => false,
    });
    expect(detectPlatform()).toBe("web");
  });

  it("classifies an installed standalone PWA as 'pwa'", async () => {
    window.matchMedia = ((q: string) => ({
      matches: q.includes("standalone"),
      media: q,
      addEventListener: () => {},
      removeEventListener: () => {},
      addListener: () => {},
      removeListener: () => {},
      onchange: null,
      dispatchEvent: () => false,
    })) as unknown as typeof window.matchMedia;

    const { detectPlatform } = await detectWith({
      getPlatform: () => "web",
      isNativePlatform: () => false,
    });
    expect(detectPlatform()).toBe("pwa");
  });
});

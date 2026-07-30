import { describe, it, expect, vi, beforeEach } from "vitest";

// Regression guard for the bug that made Android traffic look like web.
//
// The app is a Capacitor shell that loads the REMOTE site in a WebView, where
// Capacitor.isNativePlatform() can return false (see docs/android-tracking-audit.md).
// The auth screens used to decide native-vs-browser Google sign-in from that
// single signal, so Android users were routed into the browser flow — which also
// made their signups unattributable to Android.
//
// getPlatform() is the corroborating signal: it returns "android" natively and
// "web" in a browser. Neither helper may fall through to "web" when either
// signal says native.

const { mockGetPlatform, mockIsNativePlatform } = vi.hoisted(() => ({
  mockGetPlatform: vi.fn(),
  mockIsNativePlatform: vi.fn(),
}));

vi.mock("@capacitor/core", () => ({
  Capacitor: { getPlatform: mockGetPlatform, isNativePlatform: mockIsNativePlatform },
}));

beforeEach(() => {
  vi.clearAllMocks();
});

describe("native detection under a remote WebView", () => {
  it("still reports native when isNativePlatform() lies but getPlatform() says android", async () => {
    mockGetPlatform.mockReturnValue("android");
    mockIsNativePlatform.mockReturnValue(false);

    const { isNativeApp, detectPlatform } = await import("@/shared/lib/analytics/context");

    expect(isNativeApp()).toBe(true);
    expect(detectPlatform()).toBe("android");
  });

  it("trusts the bridge when it asserts native but the platform string is unexpected", async () => {
    mockGetPlatform.mockReturnValue("something-else");
    mockIsNativePlatform.mockReturnValue(true);

    const { isNativeApp } = await import("@/shared/lib/analytics/context");

    expect(isNativeApp()).toBe(true);
  });

  it("reports a plain browser as web", async () => {
    mockGetPlatform.mockReturnValue("web");
    mockIsNativePlatform.mockReturnValue(false);

    const { isNativeApp, detectPlatform } = await import("@/shared/lib/analytics/context");

    expect(isNativeApp()).toBe(false);
    expect(detectPlatform()).toBe("web");
  });

  // The auth screens read this hook to pick the Google flow, and the app promo
  // reads getAppPromoTarget — both must use the corroborated signal, otherwise
  // the Android shell offers to install itself and sends its users to the
  // browser login.
  it("hides the app promo inside the shell even when isNativePlatform() lies", async () => {
    mockGetPlatform.mockReturnValue("android");
    mockIsNativePlatform.mockReturnValue(false);

    const { getAppPromoTarget } = await import("@/shared/lib/platform");

    expect(getAppPromoTarget()).toBe("hidden");
  });
});

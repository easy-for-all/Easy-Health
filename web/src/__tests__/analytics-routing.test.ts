import { describe, it, expect, beforeEach, vi, afterEach } from "vitest";

// Destination routing (anti-duplication). The rule that keeps Android from being
// double-counted once native Firebase Analytics is live: on native the event
// goes to Firebase ONLY and GA4 (gtag) is suppressed; on web GA4 still fires.

const logFirebaseEvent = vi.fn();
let firebaseActive = false;

async function loadIndex() {
  vi.resetModules();
  vi.doMock("./firebase", () => ({
    firebaseAnalyticsActive: () => firebaseActive,
    logFirebaseEvent,
    setFirebaseScreen: vi.fn(),
    setFirebaseUserId: vi.fn(),
  }));
  // firebase.ts lives beside index.ts; mock via the same relative id it imports.
  vi.doMock("@/shared/lib/analytics/firebase", () => ({
    firebaseAnalyticsActive: () => firebaseActive,
    logFirebaseEvent,
    setFirebaseScreen: vi.fn(),
    setFirebaseUserId: vi.fn(),
  }));
  return await import("@/shared/lib/analytics/index");
}

describe("event destination routing", () => {
  beforeEach(() => {
    logFirebaseEvent.mockClear();
    (window as unknown as { gtag: ReturnType<typeof vi.fn> }).gtag = vi.fn();
    process.env.NEXT_PUBLIC_APP_ENV = "production";
  });
  afterEach(() => {
    delete process.env.NEXT_PUBLIC_APP_ENV;
    vi.doUnmock("@/shared/lib/analytics/firebase");
  });

  it("web: sends to GA4 (gtag) and NOT to Firebase", async () => {
    firebaseActive = false;
    const { trackEvent } = await loadIndex();
    trackEvent("workout_started", { a: 1 });
    const gtag = (window as unknown as { gtag: ReturnType<typeof vi.fn> }).gtag;
    expect(gtag).toHaveBeenCalledWith("event", "workout_started", { a: 1 });
    expect(logFirebaseEvent).not.toHaveBeenCalled();
  });

  it("native with Firebase active: sends to Firebase and SUPPRESSES GA4", async () => {
    firebaseActive = true;
    const { trackEvent } = await loadIndex();
    trackEvent("workout_started", { a: 1 });
    const gtag = (window as unknown as { gtag: ReturnType<typeof vi.fn> }).gtag;
    expect(gtag).not.toHaveBeenCalled();
    expect(logFirebaseEvent).toHaveBeenCalledWith("workout_started", { a: 1 });
  });
});

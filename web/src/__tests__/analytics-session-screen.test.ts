import { describe, it, expect, beforeEach } from "vitest";
import {
  SESSION_TIMEOUT_MINUTES,
  shouldStartNewSession,
  markBackgrounded,
  backgroundDurationMs,
  clearBackground,
} from "@/shared/lib/analytics/session";
import { screenNameForPath, normalizeRoute } from "@/shared/lib/analytics/screen";

describe("session windowing (30 min)", () => {
  const TIMEOUT = SESSION_TIMEOUT_MINUTES * 60 * 1000;

  beforeEach(() => clearBackground());

  it("keeps the session on a quick return (< 30 min)", () => {
    expect(shouldStartNewSession(29 * 60 * 1000, TIMEOUT)).toBe(false);
  });

  it("starts a new session after >= 30 min in background", () => {
    expect(shouldStartNewSession(TIMEOUT, TIMEOUT)).toBe(true);
    expect(shouldStartNewSession(31 * 60 * 1000, TIMEOUT)).toBe(true);
  });

  it("measures background duration from markBackgrounded", () => {
    expect(backgroundDurationMs()).toBeNull(); // never backgrounded (cold start)
    markBackgrounded(1_000);
    expect(backgroundDurationMs(1_000 + 5 * 60 * 1000)).toBe(5 * 60 * 1000);
  });
});

describe("screen name mapping (stable, non-PII)", () => {
  it("maps key routes to stable names", () => {
    expect(screenNameForPath("/")).toBe("public_home");
    expect(screenNameForPath("/login")).toBe("login");
    expect(screenNameForPath("/dashboard")).toBe("home");
    expect(screenNameForPath("/onboarding/quick")).toBe("onboarding_quick");
    expect(screenNameForPath("/workout/today")).toBe("workout_execution");
    expect(screenNameForPath("/settings/notifications")).toBe("notifications_settings");
    expect(screenNameForPath("/pricing")).toBe("paywall");
    expect(screenNameForPath("/some/unknown/route")).toBe("other");
  });

  it("never leaks ids in the normalized route", () => {
    expect(normalizeRoute("/workouts/123")).toBe("/workouts/:id");
    expect(normalizeRoute("/s/deadbeef1234")).toBe("/s/:token");
    expect(normalizeRoute("/plan")).toBe("/plan");
  });
});

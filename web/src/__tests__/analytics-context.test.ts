import { describe, it, expect, beforeEach } from "vitest";
import {
  detectAppSurface,
  detectPlatform,
  getAnonymousId,
  getSessionId,
  markInstalledOnce,
  startAnalyticsSession,
} from "@/shared/lib/analytics/context";

describe("analytics context & identity", () => {
  beforeEach(() => {
    window.localStorage.clear();
    window.sessionStorage.clear();
  });

  it("keeps a stable anonymous_id across calls (persisted)", () => {
    const a = getAnonymousId();
    const b = getAnonymousId();
    expect(a).toBe(b);
    expect(window.localStorage.getItem("eh_anon_id")).toBe(a);
  });

  it("keeps one session_id until a new session is started", () => {
    const s1 = getSessionId();
    expect(getSessionId()).toBe(s1);
    const s2 = startAnalyticsSession();
    expect(s2).not.toBe(s1);
    expect(getSessionId()).toBe(s2);
  });

  it("marks first-open only once per install", () => {
    expect(markInstalledOnce()).toBe(true);
    expect(markInstalledOnce()).toBe(false);
  });

  it("detects web platform / desktop surface outside Capacitor (jsdom)", () => {
    // jsdom is not a native Capacitor shell and matchMedia defaults to no match.
    expect(detectPlatform()).toBe("web");
    expect(["desktop_web", "mobile_web"]).toContain(detectAppSurface());
  });
});

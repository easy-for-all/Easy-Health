import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import type { AuthAttemptContext } from "@/features/auth/auth-analytics";

// Google's RECOMMENDED auth events (sign_up / login), which Google Ads reads to
// optimise Android campaigns. They are additive: the internal taxonomy events
// (signup_completed / login_completed / social_login_completed) must keep going
// out unchanged, which is asserted here too — a future refactor that "moves" an
// account creation onto the new event would silently break the product funnel.

const logFirebaseEvent = vi.fn<(name: string, params?: Record<string, unknown>) => Promise<void>>();
const trackOnce = vi.fn();
const trackEvent = vi.fn();

async function loadAuthAnalytics() {
  vi.resetModules();
  vi.doMock("@/shared/lib/analytics/firebase", () => ({ logFirebaseEvent }));
  vi.doMock("@/shared/lib/analytics", () => ({ trackEvent, trackOnce }));
  vi.doMock("@/shared/lib/analytics/context", () => ({
    getAnalyticsContext: () => ({ platform: "android" }),
  }));
  return await import("@/features/auth/auth-analytics");
}

let attemptSeq = 0;

function attempt(provider: "email" | "google"): AuthAttemptContext {
  attemptSeq += 1;
  return {
    authAttemptId: `attempt-${attemptSeq}`,
    provider,
    intent: provider === "email" ? "sign_up" : "login",
    authScreen: provider === "email" ? "sign_up" : "login",
  };
}

function recommended(name: string) {
  return logFirebaseEvent.mock.calls.filter(([eventName]) => eventName === name);
}

function internal(name: string) {
  return trackOnce.mock.calls.filter(([, eventName]) => eventName === name);
}

beforeEach(() => {
  logFirebaseEvent.mockReset();
  logFirebaseEvent.mockResolvedValue(undefined);
  trackOnce.mockReset();
  trackEvent.mockReset();
});

afterEach(() => {
  vi.doUnmock("@/shared/lib/analytics/firebase");
  vi.doUnmock("@/shared/lib/analytics");
  vi.doUnmock("@/shared/lib/analytics/context");
});

describe("A — e-mail sign-up", () => {
  it("emits sign_up { method: email } exactly once", async () => {
    const { trackSignupCompleted } = await loadAuthAnalytics();

    trackSignupCompleted(attempt("email"));

    expect(recommended("sign_up")).toHaveLength(1);
    expect(recommended("sign_up")[0][1]).toEqual({ method: "email" });
  });

  it("still emits the internal signup_completed", async () => {
    const { trackSignupCompleted } = await loadAuthAnalytics();

    trackSignupCompleted(attempt("email"));

    expect(internal("signup_completed")).toHaveLength(1);
  });
});

describe("B — new Google account", () => {
  it("emits sign_up { method: google } exactly once", async () => {
    const { trackSocialLoginCompleted } = await loadAuthAnalytics();

    await trackSocialLoginCompleted(attempt("google"), true);

    expect(recommended("sign_up")).toHaveLength(1);
    expect(recommended("sign_up")[0][1]).toEqual({ method: "google" });
    expect(recommended("login")).toHaveLength(0);
  });
});

describe("C — e-mail login", () => {
  it("emits login { method: email } exactly once", async () => {
    const { trackLoginCompleted } = await loadAuthAnalytics();

    trackLoginCompleted(attempt("email"));

    expect(recommended("login")).toHaveLength(1);
    expect(recommended("login")[0][1]).toEqual({ method: "email" });
    expect(internal("login_completed")).toHaveLength(1);
  });
});

describe("D — existing Google account", () => {
  it("emits login { method: google } exactly once", async () => {
    const { trackSocialLoginCompleted } = await loadAuthAnalytics();

    await trackSocialLoginCompleted(attempt("google"), false);

    expect(recommended("login")).toHaveLength(1);
    expect(recommended("login")[0][1]).toEqual({ method: "google" });
    expect(recommended("sign_up")).toHaveLength(0);
  });

  it("still emits the internal social_login_completed", async () => {
    const { trackSocialLoginCompleted } = await loadAuthAnalytics();

    await trackSocialLoginCompleted(attempt("google"), false);

    expect(internal("social_login_completed")).toHaveLength(1);
  });
});

describe("E — failed sign-up", () => {
  it("emits no recommended event from the failure paths", async () => {
    const { trackAuthApiError, trackAuthClientError, trackSocialLoginFailed } =
      await loadAuthAnalytics();
    const ctx = attempt("email");

    trackAuthApiError("email_signup", new Error("boom"), ctx, "backend_error");
    trackAuthClientError("email_signup", "network", ctx, "network_error");
    trackSocialLoginFailed(attempt("google"), "provider_error", "plugin_login_failed");

    expect(recommended("sign_up")).toHaveLength(0);
    expect(logFirebaseEvent).not.toHaveBeenCalled();
  });
});

describe("F — failed login", () => {
  it("emits no recommended event from the failure paths", async () => {
    const { trackAuthApiError, trackAuthClientError } = await loadAuthAnalytics();
    const ctx = attempt("email");

    trackAuthApiError("email_login", new Error("boom"), ctx, "invalid_credentials");
    trackAuthClientError("email_login", "unknown", ctx, "unknown");

    expect(recommended("login")).toHaveLength(0);
    expect(logFirebaseEvent).not.toHaveBeenCalled();
  });

  it("emits no recommended event when a Google attempt is cancelled", async () => {
    const { trackSocialLoginFailed } = await loadAuthAnalytics();

    trackSocialLoginFailed(attempt("google"), "user_cancelled", "USER_CANCELLED");

    expect(logFirebaseEvent).not.toHaveBeenCalled();
  });
});

describe("G — sign-up that also authenticates", () => {
  it("emits sign_up and NOT login for the same operation (e-mail)", async () => {
    const { trackSignupCompleted } = await loadAuthAnalytics();

    trackSignupCompleted(attempt("email"));

    expect(recommended("sign_up")).toHaveLength(1);
    expect(recommended("login")).toHaveLength(0);
  });

  it("emits sign_up and NOT login for the same operation (Google)", async () => {
    const { trackSocialLoginCompleted } = await loadAuthAnalytics();

    await trackSocialLoginCompleted(attempt("google"), true);

    expect(recommended("sign_up")).toHaveLength(1);
    expect(recommended("login")).toHaveLength(0);
  });
});

describe("H — deduplication within one attempt", () => {
  it("emits a single recommended event when the same attempt completes twice", async () => {
    const { trackSocialLoginCompleted } = await loadAuthAnalytics();
    const ctx = attempt("google");

    await trackSocialLoginCompleted(ctx, true);
    await trackSocialLoginCompleted(ctx, true);

    expect(recommended("sign_up")).toHaveLength(1);
  });

  it("does not dedupe a different attempt — a second account is a second sign_up", async () => {
    const { trackSocialLoginCompleted } = await loadAuthAnalytics();

    await trackSocialLoginCompleted(attempt("google"), true);
    await trackSocialLoginCompleted(attempt("google"), true);

    expect(recommended("sign_up")).toHaveLength(2);
  });
});

describe("I — Firebase must never break authentication", () => {
  it("resolves when the native bridge rejects", async () => {
    logFirebaseEvent.mockRejectedValue(new Error("plugin unavailable"));
    const { trackSocialLoginCompleted } = await loadAuthAnalytics();

    await expect(trackSocialLoginCompleted(attempt("google"), true)).resolves.toBeUndefined();
  });

  it("does not throw on the e-mail paths when the native bridge rejects", async () => {
    logFirebaseEvent.mockRejectedValue(new Error("plugin unavailable"));
    const { trackSignupCompleted, trackLoginCompleted } = await loadAuthAnalytics();

    expect(() => trackSignupCompleted(attempt("email"))).not.toThrow();
    expect(() => trackLoginCompleted(attempt("email"))).not.toThrow();
    // The internal telemetry still went out despite the Firebase failure.
    expect(internal("signup_completed")).toHaveLength(1);
    expect(internal("login_completed")).toHaveLength(1);
  });

  it("resolves within the budget when the bridge never settles", async () => {
    vi.useFakeTimers();
    try {
      logFirebaseEvent.mockReturnValue(new Promise<void>(() => {}));
      const { trackSocialLoginCompleted } = await loadAuthAnalytics();

      const pending = trackSocialLoginCompleted(attempt("google"), false);
      await vi.advanceTimersByTimeAsync(800);

      await expect(pending).resolves.toBeUndefined();
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("privacy", () => {
  it("sends `method` and nothing else", async () => {
    const { trackSignupCompleted, trackLoginCompleted, trackSocialLoginCompleted } =
      await loadAuthAnalytics();

    trackSignupCompleted(attempt("email"));
    trackLoginCompleted(attempt("email"));
    await trackSocialLoginCompleted(attempt("google"), true);

    expect(logFirebaseEvent).toHaveBeenCalledTimes(3);
    for (const [, params] of logFirebaseEvent.mock.calls) {
      expect(Object.keys(params ?? {})).toEqual(["method"]);
      expect(["email", "google"]).toContain((params as { method: string }).method);
    }
  });
});

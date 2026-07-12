import { resolveDeepLink, isSafeInternalPath, DEEP_LINK_FALLBACK } from "@/shared/lib/push-deep-link";

describe("push deep link allowlist", () => {
  it("accepts allowlisted internal workout paths", () => {
    expect(resolveDeepLink({ target_path: "/workouts/ready" })).toBe("/workouts/ready");
    expect(resolveDeepLink({ target_path: "/workout/today" })).toBe("/workout/today");
    expect(resolveDeepLink({ target_path: "/plan" })).toBe("/plan");
  });

  it("falls back for paths outside the allowlist", () => {
    expect(resolveDeepLink({ target_path: "/settings" })).toBe(DEEP_LINK_FALLBACK);
    expect(resolveDeepLink({ target_path: "/admin" })).toBe(DEEP_LINK_FALLBACK);
    expect(resolveDeepLink({})).toBe(DEEP_LINK_FALLBACK);
  });

  it("rejects open-redirect / external attempts", () => {
    expect(resolveDeepLink({ target_path: "https://evil.com" })).toBe(DEEP_LINK_FALLBACK);
    expect(resolveDeepLink({ target_path: "//evil.com" })).toBe(DEEP_LINK_FALLBACK);
    expect(resolveDeepLink({ target_path: "javascript:alert(1)" })).toBe(DEEP_LINK_FALLBACK);
    expect(resolveDeepLink({ target_path: "/workouts/../../etc" })).toBe("/workouts/../../etc"); // still internal, but stays in-app
  });

  it("isSafeInternalPath guards non-string and control chars", () => {
    expect(isSafeInternalPath(null)).toBe(false);
    expect(isSafeInternalPath(123)).toBe(false);
    expect(isSafeInternalPath("relative/path")).toBe(false);
    expect(isSafeInternalPath("/ok")).toBe(true);
    expect(isSafeInternalPath("/bad\npath")).toBe(false);
  });
});

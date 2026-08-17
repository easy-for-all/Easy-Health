import { describe, it, expect } from "vitest";
import { matchPattern, matchRoute, resolveExternalRoute, splitPath } from "@/native/router/match";
import { NATIVE_FALLBACK_ROUTE, NATIVE_ROUTE_PATTERNS } from "@/native/routes";

const PATTERNS = NATIVE_ROUTE_PATTERNS;

describe("matchPattern", () => {
  it("matches a static route", () => {
    expect(matchPattern("/workouts", "/workouts")).toEqual({});
  });

  it("captures a dynamic segment", () => {
    expect(matchPattern("/users/[id]", "/users/123")).toEqual({ id: "123" });
  });

  it("decodes an encoded parameter", () => {
    expect(matchPattern("/s/[token]", "/s/a%2Fb")).toEqual({ token: "a/b" });
  });

  it("rejects a different segment count", () => {
    expect(matchPattern("/users/[id]", "/users")).toBeNull();
    expect(matchPattern("/users/[id]", "/users/1/edit")).toBeNull();
  });

  it("rejects a non-matching static segment", () => {
    expect(matchPattern("/users/[id]", "/teams/1")).toBeNull();
  });
});

describe("matchRoute", () => {
  it("resolves the root route", () => {
    expect(matchRoute(PATTERNS, "/")?.pattern).toBe("/");
  });

  it("resolves a static app route", () => {
    expect(matchRoute(PATTERNS, "/workouts")?.pattern).toBe("/workouts");
  });

  it("resolves a dynamic route and exposes the id", () => {
    const match = matchRoute(PATTERNS, "/users/42");

    expect(match?.pattern).toBe("/users/[id]");
    expect(match?.params).toEqual({ id: "42" });
  });

  // /workouts/ready e /users/[id] coexistem; a estática tem que vencer
  // independentemente da ordem de registro.
  it("prefers a static route over a dynamic one of the same shape", () => {
    expect(matchRoute(PATTERNS, "/workouts/ready")?.pattern).toBe("/workouts/ready");
  });

  it("returns null for a route outside the allowlist", () => {
    expect(matchRoute(PATTERNS, "/admin/secrets")).toBeNull();
    expect(matchRoute(PATTERNS, "/nope")).toBeNull();
  });

  it("refuses anything that is not an app-relative path", () => {
    expect(matchRoute(PATTERNS, "//evil.com")).toBeNull();
    expect(matchRoute(PATTERNS, "https://evil.com/workouts")).toBeNull();
    expect(matchRoute(PATTERNS, "/workouts\n/x")).toBeNull();
  });

  it("ignores query and hash when matching", () => {
    expect(matchRoute(PATTERNS, "/workouts?from_push=9#top")?.pattern).toBe("/workouts");
  });
});

describe("splitPath", () => {
  it("separates pathname from search", () => {
    expect(splitPath("/users/1?tab=stats#x")).toEqual({ pathname: "/users/1", search: "?tab=stats" });
  });

  it("handles a path without a query", () => {
    expect(splitPath("/profile")).toEqual({ pathname: "/profile", search: "" });
  });
});

// Cold start a partir de uma rota externa (deep link, push, URL preservada pelo
// WebView). Nunca pode virar navegação arbitrária.
describe("resolveExternalRoute", () => {
  it("accepts a known relative route", () => {
    expect(resolveExternalRoute("/users/7", PATTERNS, NATIVE_FALLBACK_ROUTE)).toBe("/users/7");
  });

  it("preserves the query string of a known route", () => {
    expect(resolveExternalRoute("/workouts?from_push=3", PATTERNS, NATIVE_FALLBACK_ROUTE))
      .toBe("/workouts?from_push=3");
  });

  it("accepts an absolute easyhealth.art URL and strips the origin", () => {
    expect(resolveExternalRoute("https://easyhealth.art/users/7", PATTERNS, NATIVE_FALLBACK_ROUTE))
      .toBe("/users/7");
  });

  it("falls back for another host, even if the path is known", () => {
    expect(resolveExternalRoute("https://evil.com/users/7", PATTERNS, NATIVE_FALLBACK_ROUTE))
      .toBe(NATIVE_FALLBACK_ROUTE);
  });

  it("falls back for an unregistered route", () => {
    expect(resolveExternalRoute("/whatever", PATTERNS, NATIVE_FALLBACK_ROUTE))
      .toBe(NATIVE_FALLBACK_ROUTE);
  });

  it("falls back for junk input", () => {
    for (const input of [null, undefined, "", 42, {}, "javascript:alert(1)"]) {
      expect(resolveExternalRoute(input, PATTERNS, NATIVE_FALLBACK_ROUTE))
        .toBe(NATIVE_FALLBACK_ROUTE);
    }
  });
});

describe("route table", () => {
  it("registers the routes the acceptance scenarios exercise", () => {
    for (const pattern of ["/", "/login", "/workouts", "/profile", "/users/[id]"]) {
      expect(NATIVE_ROUTE_PATTERNS).toContain(pattern);
    }
  });

  it("has a fallback that is itself a registered route", () => {
    expect(matchRoute(PATTERNS, NATIVE_FALLBACK_ROUTE)).not.toBeNull();
  });
});

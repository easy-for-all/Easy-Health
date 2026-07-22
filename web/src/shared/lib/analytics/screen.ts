import { useEffect, useRef } from "react";
import { usePathname } from "next/navigation";
import { trackScreenView } from "./index";
import { getSessionId } from "./context";

// Screen tracking. Maps a route to a STABLE, non-PII screen name (never a user
// id or workout id) and deduplicates by (screen_name, session) so a React
// rerender never re-fires a screen_view — only a real navigation does.

const SCREEN_MAP: { test: RegExp; name: string }[] = [
  { test: /^\/$/, name: "public_home" },
  { test: /^\/login/, name: "login" },
  { test: /^\/sign-?up|^\/register/, name: "register" },
  { test: /^\/onboarding\/photo/, name: "onboarding_photo" },
  { test: /^\/onboarding\/quick/, name: "onboarding_quick" },
  { test: /^\/onboarding\/complete/, name: "onboarding_complete" },
  { test: /^\/onboarding\/ai/, name: "onboarding_ai" },
  { test: /^\/onboarding/, name: "onboarding_choice" },
  { test: /^\/dashboard|^\/home/, name: "home" },
  { test: /^\/plan/, name: "plan" },
  { test: /^\/workout\/quick/, name: "workout_execution" },
  { test: /^\/workout\/today/, name: "workout_execution" },
  { test: /^\/workout(s)?\/[^/]+\/(execute|session)/, name: "workout_execution" },
  { test: /^\/workout(s)?\/ready/, name: "generated_workout" },
  { test: /^\/workout(s)?\/[^/]+$/, name: "generated_workout" },
  { test: /^\/workout/, name: "workout_execution" },
  { test: /^\/progress|^\/history/, name: "progress" },
  { test: /^\/community/, name: "community" },
  { test: /^\/settings\/notifications/, name: "notifications_settings" },
  { test: /^\/settings/, name: "settings" },
  { test: /^\/profile/, name: "profile" },
  { test: /^\/coach/, name: "coach" },
  { test: /^\/paywall|^\/pricing/, name: "paywall" },
  { test: /^\/checkout/, name: "checkout" },
];

export function screenNameForPath(pathname: string): string {
  for (const { test, name } of SCREEN_MAP) {
    if (test.test(pathname)) return name;
  }
  return "other";
}

// Normalize dynamic segments so the route dimension stays low-cardinality and
// never carries an id (e.g. /workouts/123 -> /workouts/:id, /s/abc -> /s/:token).
export function normalizeRoute(pathname: string): string {
  return pathname
    .replace(/\/\d+(?=\/|$)/g, "/:id")
    .replace(/\/[0-9a-f]{8,}(?=\/|$)/gi, "/:token");
}

// Fires screen_view on real navigations only. Mount once (e.g. in AnalyticsBoot).
export function useScreenTracking(): void {
  const pathname = usePathname();
  const lastKey = useRef<string | null>(null);

  useEffect(() => {
    if (!pathname) return;
    const screen = screenNameForPath(pathname);
    const key = `${getSessionId()}:${screen}`;
    if (lastKey.current === key) return; // dedup: same screen in the same session
    lastKey.current = key;
    trackScreenView(screen, { route: normalizeRoute(pathname) });
  }, [pathname]);
}

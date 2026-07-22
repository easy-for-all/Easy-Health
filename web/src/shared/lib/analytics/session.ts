// Session windowing for the native app. A session ends logically after the app
// spends SESSION_TIMEOUT_MINUTES in the background; a resume within the window
// keeps the same session. Pure functions so the timing rule is unit-tested.

export const SESSION_TIMEOUT_MINUTES = 30;
const SESSION_TIMEOUT_MS = SESSION_TIMEOUT_MINUTES * 60 * 1000;

let backgroundedAt: number | null = null;

// Should a resume after `backgroundMs` in background start a NEW session?
export function shouldStartNewSession(
  backgroundMs: number,
  timeoutMs: number = SESSION_TIMEOUT_MS
): boolean {
  return backgroundMs >= timeoutMs;
}

export function markBackgrounded(now: number = Date.now()): void {
  backgroundedAt = now;
}

// Milliseconds spent in background since the last markBackgrounded, or null if
// we never went to background (e.g. cold start).
export function backgroundDurationMs(now: number = Date.now()): number | null {
  return backgroundedAt == null ? null : now - backgroundedAt;
}

export function clearBackground(): void {
  backgroundedAt = null;
}

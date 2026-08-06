// One id per authentication attempt, shared by every event that attempt emits.
//
// Without it, a cancelled picker, the retry that follows it and the failure of a
// third try are three unrelated rows: the funnel can count them but cannot tell
// whether it is watching one person struggling or three people arriving.
//
// Deliberately dependency-free: shared/lib/api.ts reads it to set the
// X-Auth-Attempt-Id header, and api.ts must not gain an import cycle.
//
// The id is opaque and random. It is never derived from an e-mail, a user id or
// anything else that could identify a person.

let currentId: string | null = null;

function newId(): string {
  // Same fallback shape used by analytics/server.ts for idempotency keys: older
  // Android WebViews expose `crypto` without randomUUID.
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

/**
 * Opens a new attempt and returns its id. Always mints a fresh id — a retry
 * after a cancellation or a failure is a NEW attempt, never a continuation.
 */
export function startAuthAttempt(): string {
  currentId = newId();
  return currentId;
}

/** The attempt in flight, or null between attempts. */
export function currentAuthAttemptId(): string | null {
  return currentId;
}

/**
 * Closes the attempt on any terminal outcome — success, technical failure or
 * cancellation. Requests made outside an attempt carry no attempt header.
 */
export function endAuthAttempt(): void {
  currentId = null;
}

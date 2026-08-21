// Storage access that never throws.
//
// Reading `window.localStorage` ITSELF raises SecurityError when the browser
// blocks storage for the document ("block all cookies", restricted in-app
// WebViews, a sandboxed iframe) — the failure is the property access, not the
// getItem call, so the try has to wrap the access too. A single unguarded read
// in the root layout was enough to take the whole landing page down through
// app/global-error.tsx (Sentry RUBY-RAILS-K).
//
// When the real store is unreachable, values live in a Map for the lifetime of
// the page: writes stay readable within the session, which is all that
// same-document handoffs (e.g. wk_quick_day) need. Same idea as the in-memory
// session id in analytics/context.ts.

type Backend = "local" | "session";

function rawStore(backend: Backend): Storage | null {
  if (typeof window === "undefined") return null;
  try {
    // The property access is the part that throws.
    return backend === "local" ? window.localStorage : window.sessionStorage;
  } catch {
    return null;
  }
}

// localStorage and sessionStorage are blocked independently by some browsers,
// so availability is resolved per backend and never shared.
function createSafeStorage(backend: Backend) {
  const memory = new Map<string, string>();
  let available: boolean | undefined;

  function isAvailable(): boolean {
    if (available === undefined) {
      const store = rawStore(backend);
      if (!store) {
        available = false;
      } else {
        // Reachable is not the same as usable: Safari private mode hands back a
        // store whose setItem throws on quota.
        const probe = "__eh_probe__";
        try {
          store.setItem(probe, "1");
          store.removeItem(probe);
          available = true;
        } catch {
          available = false;
        }
      }
    }
    return available;
  }

  return {
    isAvailable,

    get(key: string): string | null {
      if (isAvailable()) {
        try {
          return rawStore(backend)!.getItem(key);
        } catch {
          /* fall through to memory */
        }
      }
      return memory.get(key) ?? null;
    },

    set(key: string, value: string): void {
      if (isAvailable()) {
        try {
          rawStore(backend)!.setItem(key, value);
          return;
        } catch {
          /* quota or a store that turned hostile mid-session — keep it in memory */
        }
      }
      memory.set(key, value);
    },

    remove(key: string): void {
      memory.delete(key);
      if (!isAvailable()) return;
      try {
        rawStore(backend)!.removeItem(key);
      } catch {
        /* nothing to clean up */
      }
    },
  };
}

export const safeLocal = createSafeStorage("local");
export const safeSession = createSafeStorage("session");

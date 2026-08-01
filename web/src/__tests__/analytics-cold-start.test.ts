import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";

// Cold start regression suite. lifecycle.ts had NO test file, which is exactly
// why it shipped emitting two different session_ids in a single cold start and
// emitting the first events before installation_id had resolved.
//
// The events are asserted on the SERVER QUEUE (what actually reaches
// product_analytics_events), not on trackEvent calls — the bug lived in the
// context snapshot taken at enqueue time, so a spy on trackEvent would have
// been green while production was broken.

const enqueued: Array<{ name: string; properties: Record<string, unknown> }> = [];
const capturedContexts: Array<{ name: string; session_id: string; installation_id?: string }> = [];

vi.mock("@capacitor/core", () => ({
  Capacitor: {
    isNativePlatform: () => true,
    getPlatform: () => "android",
  },
}));

vi.mock("@capacitor/app", () => ({
  App: {
    getInfo: async () => ({ version: "1.4.0", build: "50" }),
    addListener: vi.fn(),
  },
}));

// Records what the server sender WOULD have shipped, with the context resolved
// the same way buildEvent resolves it.
vi.mock("@/shared/lib/analytics/server", async () => {
  const ctx = await import("@/shared/lib/analytics/context");
  return {
    isServerEvent: () => true,
    flushOnBackground: vi.fn(),
    enqueueServerEvent: (name: string, _v: number, properties: Record<string, unknown>) => {
      const snapshot = ctx.getAnalyticsContext();
      enqueued.push({ name, properties });
      capturedContexts.push({
        name,
        session_id: snapshot.session_id,
        installation_id: snapshot.installation_id,
      });
    },
  };
});

async function runColdStart() {
  const { setCachedInstallationId } = await import("@/shared/lib/analytics/context");
  // Stands in for the resolved @capacitor/preferences read that init.ts awaits
  // before the lifecycle runs.
  setCachedInstallationId("install-abc-123");

  const { initAnalyticsLifecycle } = await import("@/shared/lib/analytics/lifecycle");
  await initAnalyticsLifecycle();
}

describe("android cold start", () => {
  beforeEach(() => {
    // trackEvent short-circuits every sink when the environment reads "test"
    // (analytics must never emit from an automated run), so the boot has to be
    // observed under a non-test environment or nothing is queued at all.
    process.env.NEXT_PUBLIC_APP_ENV = "production";
    enqueued.length = 0;
    capturedContexts.length = 0;
    window.localStorage.clear();
    window.sessionStorage.clear();
    vi.resetModules();
  });

  afterEach(() => {
    delete process.env.NEXT_PUBLIC_APP_ENV;
  });

  it("emits app_first_open exactly once, and not on the next cold start", async () => {
    await runColdStart();
    expect(enqueued.filter((e) => e.name === "app_first_open")).toHaveLength(1);

    // Second boot: same install (localStorage survives), lifecycle module reset.
    vi.resetModules();
    enqueued.length = 0;
    await runColdStart();

    expect(enqueued.filter((e) => e.name === "app_first_open")).toHaveLength(0);
    expect(enqueued.filter((e) => e.name === "app_opened")).toHaveLength(1);
  });

  it("gives app_first_open, app_opened and session_started ONE session_id", async () => {
    await runColdStart();

    const names = capturedContexts.map((e) => e.name);
    expect(names).toContain("app_first_open");
    expect(names).toContain("app_opened");
    expect(names).toContain("session_started");

    const sessions = new Set(capturedContexts.map((e) => e.session_id));
    expect(sessions.size).toBe(1);
    // And it is the session that survived, not one discarded right after.
    expect([...sessions][0]).toBe(window.sessionStorage.getItem("eh_session_id"));
  });

  it("carries installation_id on every event of the first cold start", async () => {
    await runColdStart();

    expect(capturedContexts.length).toBeGreaterThan(0);
    for (const event of capturedContexts) {
      expect(event.installation_id, `${event.name} lost installation_id`).toBe("install-abc-123");
    }
  });

  it("is idempotent: a second invocation adds no duplicate events", async () => {
    const { initAnalyticsLifecycle } = await import("@/shared/lib/analytics/lifecycle");
    const { setCachedInstallationId } = await import("@/shared/lib/analytics/context");
    setCachedInstallationId("install-abc-123");

    await initAnalyticsLifecycle();
    const afterFirst = enqueued.length;
    await initAnalyticsLifecycle();

    expect(enqueued.length).toBe(afterFirst);
  });
});

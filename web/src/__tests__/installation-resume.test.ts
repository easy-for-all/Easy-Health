import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// Resume is the app's self-heal moment: a register that did NOT materialise at
// boot (network failure, or a 202 the backend accepted without writing) gets
// another chance when the user comes back. It must produce exactly one new POST
// per resume — never a storm, and never nothing.

const REGISTER_PATH = "/api/v1/app/installations/register";

type StateListener = (state: { isActive: boolean }) => void;

const listeners: Record<string, StateListener> = {};

function mockCapacitor() {
  vi.doMock("@capacitor/core", () => ({
    Capacitor: { getPlatform: () => "android", isNativePlatform: () => true },
  }));
  vi.doMock("@capacitor/app", () => ({
    App: {
      getInfo: async () => ({ version: "1.0.0", build: "50" }),
      addListener: (event: string, cb: StateListener) => {
        listeners[event] = cb;
        return { remove: () => undefined };
      },
    },
  }));
}

// Boot as init.ts does it: lifecycle listeners plus the app-boot register.
async function boot() {
  vi.resetModules();
  mockCapacitor();
  const lifecycle = await import("@/shared/lib/analytics/lifecycle");
  const installation = await import("@/shared/lib/analytics/installation");
  await lifecycle.initAnalyticsLifecycle();
  await installation.ensureInstallationRegistered({}, { sessionStarted: true });
  return installation;
}

function resume() {
  listeners.appStateChange?.({ isActive: false });
  listeners.appStateChange?.({ isActive: true });
}

function fetchDeferred() {
  return vi.fn(async () => ({
    ok: true,
    status: 202,
    statusText: "Accepted",
    json: async () => ({ status: "deferred", registered: false, retryable: true }),
  }));
}

function fetchRegistered() {
  return vi.fn(async () => ({
    ok: true,
    status: 201,
    statusText: "Created",
    json: async () => ({ status: "registered", registered: true, installation_id: "x", created: true }),
  }));
}

function registerCalls(mock: ReturnType<typeof fetchDeferred>): unknown[] {
  return mock.mock.calls.filter((call) => String(call[0]).includes(REGISTER_PATH));
}

// The resume handler never awaits the register (the resume path must stay
// instant), so assertions wait for the call to actually leave.
async function settle() {
  for (let i = 0; i < 5; i++) await new Promise((resolve) => setTimeout(resolve, 0));
}

describe("installation register on resume", () => {
  beforeEach(() => {
    window.localStorage.clear();
    for (const key of Object.keys(listeners)) delete listeners[key];
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.doUnmock("@capacitor/core");
    vi.doUnmock("@capacitor/app");
    vi.resetModules();
    vi.restoreAllMocks();
  });

  it("POSTs again on resume after the boot register was only deferred", async () => {
    const fetchMock = fetchDeferred();
    vi.stubGlobal("fetch", fetchMock);

    await boot();
    const afterBoot = registerCalls(fetchMock).length;

    resume();
    await settle();

    // The 202 left nothing registered, so the resume is a real retry.
    expect(afterBoot).toBe(1);
    expect(registerCalls(fetchMock)).toHaveLength(2);
  });

  it("does not re-POST on resume once the register really succeeded", async () => {
    const fetchMock = fetchRegistered();
    vi.stubGlobal("fetch", fetchMock);

    await boot();
    resume();
    await settle();

    expect(registerCalls(fetchMock)).toHaveLength(1);
  });

  it("keeps repeated resumes single-flight instead of a request storm", async () => {
    let release: (() => void) | undefined;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const fetchMock = vi.fn(async () => {
      await gate;
      return {
        ok: true, status: 202, statusText: "Accepted",
        json: async () => ({ status: "deferred", registered: false, retryable: true }),
      };
    });
    vi.stubGlobal("fetch", fetchMock);

    vi.resetModules();
    mockCapacitor();
    const lifecycle = await import("@/shared/lib/analytics/lifecycle");
    await lifecycle.initAnalyticsLifecycle();

    resume();
    resume();
    resume();
    await settle();

    // Every resume shares the in-flight operation: one POST, not three.
    expect(registerCalls(fetchMock)).toHaveLength(1);
    release?.();
    await settle();
  });
});

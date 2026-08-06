import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// Leaving the app used to be able to take the tail of a session with it: the
// queue is debounced by 3s and the native background transition only enqueued
// app_backgrounded, never flushing. The events most likely to be lost that way
// are exactly the ones that explain why someone left — an auth failure, a
// cancelled picker — because leaving is what immediately follows them.

type StateListener = (state: { isActive: boolean }) => void;

const listeners: Record<string, StateListener> = {};
const tracked: string[] = [];
const flushOnBackground = vi.fn();

function mockCapacitor() {
  vi.doMock("@capacitor/core", () => ({
    Capacitor: { getPlatform: () => "android", isNativePlatform: () => true },
  }));
  vi.doMock("@capacitor/app", () => ({
    App: {
      getInfo: async () => ({ version: "1.0.0", build: "60" }),
      addListener: (event: string, cb: StateListener) => {
        listeners[event] = cb;
        return { remove: () => undefined };
      },
    },
  }));
  // The queue itself is not under test here; what matters is that the lifecycle
  // both enqueues the event and asks the existing sender to drain.
  vi.doMock("@/shared/lib/analytics/server", () => ({
    isServerEvent: (name: string) => {
      tracked.push(name);
      return false;
    },
    enqueueServerEvent: vi.fn(),
    flushOnBackground,
  }));
}

async function boot() {
  vi.resetModules();
  mockCapacitor();
  const lifecycle = await import("@/shared/lib/analytics/lifecycle");
  await lifecycle.initAnalyticsLifecycle();
}

function background() {
  listeners.appStateChange?.({ isActive: false });
}

beforeEach(() => {
  // trackEvent short-circuits every sink under the "test" environment.
  process.env.NEXT_PUBLIC_APP_ENV = "production";
  tracked.length = 0;
  flushOnBackground.mockReset();
  window.localStorage.clear();
  window.sessionStorage.clear();
});

afterEach(() => {
  delete process.env.NEXT_PUBLIC_APP_ENV;
});

describe("app going to the background", () => {
  it("enqueues app_backgrounded and asks the existing sender to flush", async () => {
    await boot();
    tracked.length = 0;

    background();

    expect(tracked).toContain("app_backgrounded");
    expect(flushOnBackground).toHaveBeenCalledTimes(1);
  });

  it("survives a flush that throws — telemetry must not break the transition", async () => {
    await boot();
    flushOnBackground.mockImplementation(() => {
      throw new Error("beacon unavailable");
    });

    expect(() => background()).not.toThrow();
    expect(flushOnBackground).toHaveBeenCalled();
  });

  it("does not flush again while the app stays in the background", async () => {
    await boot();

    background();
    background();

    expect(flushOnBackground).toHaveBeenCalledTimes(1);
  });
});

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// ---------------------------------------------------------------------------
// Controllable fakes for the Capacitor plugins + api client. The push service
// uses dynamic `import()`, which vi.mock intercepts as well.
// ---------------------------------------------------------------------------
const h = vi.hoisted(() => {
  const listeners: Record<string, Array<(arg: unknown) => void>> = {};
  const state = {
    isNative: true,
    checkReceive: "granted" as string,
    requestReceive: "granted" as string,
    // What register() does when called (default: emit a token synchronously).
    onRegister: null as null | (() => void),
    listeners,
    emit(event: string, arg: unknown) {
      (listeners[event] ?? []).slice().forEach((cb) => cb(arg));
    },
    reset() {
      for (const k of Object.keys(listeners)) delete listeners[k];
      state.isNative = true;
      state.checkReceive = "granted";
      state.requestReceive = "granted";
      state.onRegister = () => state.emit("registration", { value: "fcm-token-abcd1234" });
    },
  };
  return state;
});

class MockApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

const apiPost = vi.hoisted(() => vi.fn());
const trackEventMock = vi.hoisted(() => vi.fn());

vi.mock("@capacitor/core", () => ({
  Capacitor: { isNativePlatform: () => h.isNative },
}));

vi.mock("@capacitor/app", () => ({
  App: { getInfo: vi.fn(async () => ({ version: "9.9.9" })) },
}));

vi.mock("@capacitor/push-notifications", () => ({
  PushNotifications: {
    checkPermissions: vi.fn(async () => ({ receive: h.checkReceive })),
    requestPermissions: vi.fn(async () => {
      // Mirror a real device: after the prompt resolves, checkPermissions
      // reflects the user's choice.
      h.checkReceive = h.requestReceive;
      return { receive: h.requestReceive };
    }),
    register: vi.fn(async () => {
      h.onRegister?.();
    }),
    createChannel: vi.fn(async () => {}),
    addListener: vi.fn(async (event: string, cb: (arg: unknown) => void) => {
      (h.listeners[event] ??= []).push(cb);
      return {
        remove: vi.fn(async () => {
          const arr = h.listeners[event];
          if (arr) {
            const i = arr.indexOf(cb);
            if (i >= 0) arr.splice(i, 1);
          }
        }),
      };
    }),
  },
}));

vi.mock("@/shared/lib/api", () => ({
  api: { post: apiPost },
  ApiError: MockApiError,
}));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: trackEventMock,
}));

async function loadService() {
  return await import("@/shared/lib/pushNotifications");
}

beforeEach(() => {
  vi.resetModules();
  h.reset();
  apiPost.mockReset();
  apiPost.mockResolvedValue({ id: 1, enabled: true });
  trackEventMock.mockReset();
  localStorage.clear();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("ensurePushTokenRegistered", () => {
  it("registers and posts once when permission is already granted", async () => {
    const svc = await loadService();
    const result = await svc.ensurePushTokenRegistered("permission_granted");

    expect(result).toEqual({ permissionState: "granted", registered: true });
    expect(apiPost).toHaveBeenCalledTimes(1);
    const [path, body] = apiPost.mock.calls[0];
    expect(path).toBe("/api/v1/device_tokens");
    expect(body).toMatchObject({
      token: "fcm-token-abcd1234",
      platform: "android",
      permission_status: "granted",
      app_version: "9.9.9",
    });
  });

  it("never leaks the raw token into analytics events", async () => {
    const svc = await loadService();
    await svc.ensurePushTokenRegistered("auth_boot");
    const serialized = JSON.stringify(trackEventMock.mock.calls);
    expect(serialized).not.toContain("fcm-token-abcd1234");
  });

  it("emits a callback-received then a backend-sync-succeeded event", async () => {
    const svc = await loadService();
    await svc.ensurePushTokenRegistered("auth_boot");
    const events = trackEventMock.mock.calls.map((c) => c[0]);
    expect(events).toContain("push_registration_callback_received");
    expect(events).toContain("push_backend_sync_succeeded");
  });

  it("registers even when the pre-permission card was already answered", async () => {
    localStorage.setItem("eh_push_prepermission_answered", "1");
    const svc = await loadService();
    const result = await svc.ensurePushTokenRegistered("permission_granted");
    expect(result.registered).toBe(true);
    expect(apiPost).toHaveBeenCalledTimes(1);
  });

  it("dedupes concurrent calls into a single operation (one POST)", async () => {
    const svc = await loadService();
    const [a, b] = await Promise.all([
      svc.ensurePushTokenRegistered("auth_boot"),
      svc.ensurePushTokenRegistered("login"),
    ]);
    expect(a.registered).toBe(true);
    expect(b.registered).toBe(true);
    expect(apiPost).toHaveBeenCalledTimes(1);
  });

  it("stays idempotent when called again after a success", async () => {
    const svc = await loadService();
    const first = await svc.ensurePushTokenRegistered("auth_boot");
    const second = await svc.ensurePushTokenRegistered("auth_boot");
    expect(first.registered).toBe(true);
    expect(second.registered).toBe(true);
  });

  it("returns unsupported and does nothing on a non-native platform", async () => {
    h.isNative = false;
    const svc = await loadService();
    const result = await svc.ensurePushTokenRegistered("auth_boot");
    expect(result).toEqual({ permissionState: "unsupported", registered: false, failureReason: "unsupported" });
    expect(apiPost).not.toHaveBeenCalled();
  });

  it("does not register when permission is not granted", async () => {
    h.checkReceive = "prompt";
    const svc = await loadService();
    const result = await svc.ensurePushTokenRegistered("auth_boot");
    expect(result.registered).toBe(false);
    expect(result.failureReason).toBe("permission_denied");
    expect(apiPost).not.toHaveBeenCalled();
  });

  it("reports registration_error and does not crash when registration fails", async () => {
    h.onRegister = () => h.emit("registrationError", { error: "no play services" });
    const svc = await loadService();
    const result = await svc.ensurePushTokenRegistered("auth_boot");
    expect(result).toEqual({ permissionState: "granted", registered: false, failureReason: "registration_error" });
    expect(apiPost).not.toHaveBeenCalled();
  });

  it("does not mark registered when the backend rejects with a 4xx", async () => {
    apiPost.mockReset();
    apiPost.mockRejectedValue(new MockApiError("bad request", 422));
    const svc = await loadService();
    const result = await svc.ensurePushTokenRegistered("auth_boot");
    expect(result.registered).toBe(false);
    expect(result.failureReason).toBe("backend_sync_failed");
    expect(apiPost).toHaveBeenCalledTimes(1); // 4xx is not retried
  });

  it("retries a transient backend failure exactly once and then succeeds", async () => {
    vi.useFakeTimers();
    apiPost.mockReset();
    apiPost
      .mockRejectedValueOnce(new MockApiError("server error", 503))
      .mockResolvedValueOnce({ id: 1, enabled: true });

    const svc = await loadService();
    const promise = svc.ensurePushTokenRegistered("auth_boot");
    await vi.advanceTimersByTimeAsync(1000); // clear the 800ms retry backoff
    const result = await promise;

    expect(result.registered).toBe(true);
    expect(apiPost).toHaveBeenCalledTimes(2);
  });

  it("times out cleanly when the registration callback never arrives", async () => {
    vi.useFakeTimers();
    h.onRegister = () => {}; // native never emits a token
    const svc = await loadService();
    const promise = svc.ensurePushTokenRegistered("auth_boot");
    await vi.advanceTimersByTimeAsync(16_000);
    const result = await promise;

    expect(result).toEqual({ permissionState: "granted", registered: false, failureReason: "registration_timeout" });
    expect(apiPost).not.toHaveBeenCalled();
    // Per-op listeners were removed on timeout — nothing left attached.
    expect(h.listeners["registration"]?.length ?? 0).toBe(0);
  });

  it("a delayed callback after a timeout cannot resolve a later operation", async () => {
    vi.useFakeTimers();
    h.onRegister = () => {}; // op A never emits -> will time out
    const svc = await loadService();
    const opA = svc.ensurePushTokenRegistered("auth_boot");
    await vi.advanceTimersByTimeAsync(16_000);
    expect((await opA).failureReason).toBe("registration_timeout");

    // Op A's native callback arrives late — its listener is already gone.
    h.emit("registration", { value: "STALE-TOKEN-from-A" });
    expect(apiPost).not.toHaveBeenCalled();

    // Op B registers normally with its own token.
    vi.useRealTimers();
    h.onRegister = () => h.emit("registration", { value: "fresh-token-B" });
    const resultB = await svc.ensurePushTokenRegistered("login");
    expect(resultB.registered).toBe(true);
    expect(apiPost).toHaveBeenCalledTimes(1);
    expect(apiPost.mock.calls[0][1]).toMatchObject({ token: "fresh-token-B" });
  });
});

describe("requestPushPermissionAndRegister", () => {
  it("prompts, registers and posts when the user accepts", async () => {
    h.checkReceive = "prompt";
    h.requestReceive = "granted";
    const svc = await loadService();
    const result = await svc.requestPushPermissionAndRegister();
    expect(result).toEqual({ permissionState: "granted", registered: true });
    expect(apiPost).toHaveBeenCalledTimes(1);
  });

  it("returns permission_denied without posting when the user rejects", async () => {
    h.checkReceive = "prompt";
    h.requestReceive = "denied";
    const svc = await loadService();
    const result = await svc.requestPushPermissionAndRegister();
    expect(result.registered).toBe(false);
    expect(result.failureReason).toBe("permission_denied");
    expect(apiPost).not.toHaveBeenCalled();
  });
});

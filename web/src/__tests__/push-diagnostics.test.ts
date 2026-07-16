import { describe, it, expect, vi, beforeEach } from "vitest";

// Fakes for the Capacitor plugins + api client used by the diagnostics helpers.
const h = vi.hoisted(() => {
  const listeners: Record<string, Array<(arg: unknown) => void>> = {};
  return {
    isNative: true,
    checkReceive: "granted" as string,
    listeners,
    openAndroid: null as null | ((opts: unknown) => void),
    localDisplay: "granted" as string,
    reset() {
      for (const k of Object.keys(listeners)) delete listeners[k];
      this.isNative = true;
      this.checkReceive = "granted";
      this.openAndroid = null;
      this.localDisplay = "granted";
    },
  };
});

class MockApiError extends Error {
  status: number;
  errorCode?: string;
  constructor(message: string, status: number, errorCode?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.errorCode = errorCode;
  }
}

const apiPost = vi.hoisted(() => vi.fn());
const nativeSettingsOpen = vi.hoisted(() => vi.fn());
const localSchedule = vi.hoisted(() => vi.fn());

vi.mock("@capacitor/core", () => ({
  Capacitor: { isNativePlatform: () => h.isNative, getPlatform: () => (h.isNative ? "android" : "web") },
}));
vi.mock("@capacitor/app", () => ({
  App: { getInfo: vi.fn(async () => ({ version: "9.9.9", build: "42" })) },
}));
vi.mock("@capacitor/push-notifications", () => ({
  PushNotifications: {
    checkPermissions: vi.fn(async () => ({ receive: h.checkReceive })),
    requestPermissions: vi.fn(async () => ({ receive: h.checkReceive })),
    register: vi.fn(async () => h.listeners.registration?.forEach((cb) => cb({ value: "fcm-token-abcd1234" }))),
    createChannel: vi.fn(async () => {}),
    addListener: vi.fn(async (event: string, cb: (arg: unknown) => void) => {
      (h.listeners[event] ??= []).push(cb);
      return { remove: vi.fn(async () => {}) };
    }),
  },
}));
vi.mock("capacitor-native-settings", () => ({
  NativeSettings: { openAndroid: nativeSettingsOpen },
  AndroidSettings: { AppNotification: "app_notification" },
}));
vi.mock("@capacitor/local-notifications", () => ({
  LocalNotifications: {
    checkPermissions: vi.fn(async () => ({ display: h.localDisplay })),
    requestPermissions: vi.fn(async () => ({ display: h.localDisplay })),
    createChannel: vi.fn(async () => {}),
    schedule: localSchedule,
  },
}));
vi.mock("@/shared/lib/api", () => ({ api: { post: apiPost }, ApiError: MockApiError }));
vi.mock("@/shared/lib/analytics", () => ({ trackEvent: vi.fn() }));

async function loadService() {
  return await import("@/shared/lib/pushNotifications");
}

beforeEach(() => {
  vi.resetModules();
  h.reset();
  apiPost.mockReset();
  apiPost.mockResolvedValue({ ok: true });
  nativeSettingsOpen.mockReset();
  localSchedule.mockReset();
  localStorage.clear();
});

describe("collectPushDiagnostics", () => {
  it("reports unsupported on the web (non-native)", async () => {
    h.isNative = false;
    const svc = await loadService();
    const snap = await svc.collectPushDiagnostics();
    expect(snap.isNative).toBe(false);
    expect(snap.permissionState).toBe("unsupported");
    expect(snap.platform).toBe("web");
  });

  it("reflects a masked token after registration and never exposes the raw token", async () => {
    const svc = await loadService();
    await svc.ensurePushTokenRegistered("permission_granted");
    const snap = await svc.collectPushDiagnostics();

    expect(snap.tokenSyncedToApi).toBe(true);
    expect(snap.lastApiStatus).toBe("ok");
    expect(snap.maskedToken).toBe("fcm-…1234");
    expect(snap.appVersion).toBe("9.9.9");
    expect(snap.build).toBe("42");
    // The raw token must never leak through the snapshot.
    expect(JSON.stringify(snap)).not.toContain("fcm-token-abcd1234");
  });

  it("records a failed backend sync in the snapshot", async () => {
    apiPost.mockRejectedValue(new MockApiError("bad", 422, "invalid"));
    const svc = await loadService();
    await svc.ensurePushTokenRegistered("permission_granted");
    const snap = await svc.collectPushDiagnostics();
    expect(snap.tokenSyncedToApi).toBe(false);
    expect(snap.lastApiStatus).toBe(422);
  });
});

describe("openAppNotificationSettings", () => {
  it("no-ops on web", async () => {
    h.isNative = false;
    const svc = await loadService();
    expect(await svc.openAppNotificationSettings()).toBe(false);
    expect(nativeSettingsOpen).not.toHaveBeenCalled();
  });

  it("invokes the native settings intent on Android", async () => {
    const svc = await loadService();
    expect(await svc.openAppNotificationSettings()).toBe(true);
    expect(nativeSettingsOpen).toHaveBeenCalledWith({ option: "app_notification" });
  });
});

describe("sendLocalTestNotification", () => {
  it("no-ops on web", async () => {
    h.isNative = false;
    const svc = await loadService();
    expect(await svc.sendLocalTestNotification()).toBe(false);
    expect(localSchedule).not.toHaveBeenCalled();
  });

  it("schedules a local notification on the workout_reminders channel", async () => {
    const svc = await loadService();
    expect(await svc.sendLocalTestNotification()).toBe(true);
    const arg = localSchedule.mock.calls[0][0];
    expect(arg.notifications[0].channelId).toBe("workout_reminders");
  });

  it("returns false when local permission is denied", async () => {
    h.localDisplay = "denied";
    const svc = await loadService();
    expect(await svc.sendLocalTestNotification()).toBe(false);
  });
});

describe("requestApiTestPush", () => {
  it("posts to the admin self-only endpoint", async () => {
    const svc = await loadService();
    const res = await svc.requestApiTestPush();
    expect(res.ok).toBe(true);
    expect(apiPost).toHaveBeenCalledWith("/api/v1/admin/push_test", {});
  });

  it("surfaces the API error code/status on failure", async () => {
    apiPost.mockRejectedValue(new MockApiError("forbidden", 403, "not_admin"));
    const svc = await loadService();
    const res = await svc.requestApiTestPush();
    expect(res).toMatchObject({ ok: false, status: 403, errorCode: "not_admin" });
  });
});

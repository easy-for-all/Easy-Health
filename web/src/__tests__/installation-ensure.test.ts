import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// ensureInstallationRegistered is the single entry point that guarantees the
// installation exists locally and, when possible, on the backend. It closes the
// race where a login authenticated before the id was resolved, so the request
// that created the session went out without X-Installation-Id.

const REGISTER_PATH = "/api/v1/app/installations/register";

function nativeCapacitor() {
  return { Capacitor: { getPlatform: () => "android", isNativePlatform: () => true } };
}

function webCapacitor() {
  return { Capacitor: { getPlatform: () => "web", isNativePlatform: () => false } };
}

async function loadNative() {
  vi.resetModules();
  vi.doMock("@capacitor/core", () => nativeCapacitor());
  return await import("@/shared/lib/analytics/installation");
}

async function loadWeb() {
  vi.resetModules();
  vi.doMock("@capacitor/core", () => webCapacitor());
  return await import("@/shared/lib/analytics/installation");
}

function fetchOk() {
  return vi.fn(async () => ({ ok: true, status: 200, statusText: "OK", json: async () => ({}) }));
}

function fetchStatus(status: number) {
  return vi.fn(async () => ({
    ok: false,
    status,
    statusText: "Error",
    json: async () => ({ error: "nope" }),
  }));
}

function registerCalls(mock: ReturnType<typeof fetchOk>): unknown[] {
  return mock.mock.calls.filter((call) => String(call[0]).includes(REGISTER_PATH));
}

describe("ensureInstallationRegistered", () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.useRealTimers();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.doUnmock("@capacitor/core");
    vi.resetModules();
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("resolves the id and registers it remotely on first boot", async () => {
    const fetchMock = fetchOk();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadNative();

    const result = await ensureInstallationRegistered({}, { sessionStarted: true });

    expect(result.installationId).toBeTruthy();
    expect(result.remoteRegistered).toBe(true);
    expect(result.failureCode).toBeUndefined();
    expect(registerCalls(fetchMock)).toHaveLength(1);
    expect(window.localStorage.getItem("eh_installation_id")).toBe(result.installationId);
  });

  it("reuses an id already persisted instead of creating a second one", async () => {
    window.localStorage.setItem("eh_installation_id", "existing-id");
    vi.stubGlobal("fetch", fetchOk());
    const { ensureInstallationRegistered } = await loadNative();

    const result = await ensureInstallationRegistered();

    expect(result.installationId).toBe("existing-id");
  });

  it("shares one operation between concurrent callers (boot, login, push, resume)", async () => {
    const fetchMock = fetchOk();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadNative();

    const results = await Promise.all([
      ensureInstallationRegistered(),
      ensureInstallationRegistered(),
      ensureInstallationRegistered(),
    ]);

    expect(registerCalls(fetchMock)).toHaveLength(1);
    expect(new Set(results.map((r) => r.installationId)).size).toBe(1);
  });

  it("does not re-POST once the register succeeded in this app cycle", async () => {
    const fetchMock = fetchOk();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadNative();

    await ensureInstallationRegistered();
    await ensureInstallationRegistered();
    await ensureInstallationRegistered();

    expect(registerCalls(fetchMock)).toHaveLength(1);
  });

  it("still returns the local id when the backend register fails", async () => {
    vi.stubGlobal("fetch", fetchStatus(500));
    const { ensureInstallationRegistered } = await loadNative();

    const result = await ensureInstallationRegistered();

    expect(result.installationId).toBeTruthy();
    expect(result.remoteRegistered).toBe(false);
    expect(result.failureCode).toBe("transient");
  });

  it("retries a transient failure once, but never a 4xx", async () => {
    vi.stubGlobal("fetch", fetchStatus(500));
    const native = await loadNative();
    await native.ensureInstallationRegistered();
    // 2 attempts for a 5xx.
    expect(registerCalls(globalThis.fetch as ReturnType<typeof fetchOk>)).toHaveLength(2);

    const clientError = fetchStatus(422);
    vi.stubGlobal("fetch", clientError);
    const fresh = await loadNative();
    const result = await fresh.ensureInstallationRegistered();

    expect(registerCalls(clientError)).toHaveLength(1);
    expect(result.failureCode).toBe("client_error");
  });

  it("retries on a later call after a failure, unlike after a success", async () => {
    vi.stubGlobal("fetch", fetchStatus(500));
    const { ensureInstallationRegistered } = await loadNative();

    await ensureInstallationRegistered();
    const failed = registerCalls(globalThis.fetch as ReturnType<typeof fetchOk>).length;
    await ensureInstallationRegistered();

    expect(registerCalls(globalThis.fetch as ReturnType<typeof fetchOk>).length)
      .toBeGreaterThan(failed);
  });

  it("is a no-op on web/PWA — a browser carries no installation", async () => {
    const fetchMock = fetchOk();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadWeb();

    const result = await ensureInstallationRegistered();

    expect(result.failureCode).toBe("unsupported");
    expect(result.installationId).toBeNull();
    expect(registerCalls(fetchMock)).toHaveLength(0);
  });

  it("registers regardless of build: app_build is metadata, never a gate", async () => {
    const fetchMock = fetchOk();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadNative();

    const result = await ensureInstallationRegistered();

    const [ , init ] = registerCalls(fetchMock)[0] as [string, RequestInit];
    const body = JSON.parse(String(init.body));
    expect(body.installation_id).toBe(result.installationId);
    expect(body.platform).toBe("android");
    // No build could be read in jsdom, and the register happened anyway.
    expect(body.app_build).toBeUndefined();
  });
});

describe("ensureInstallationForAuth", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.doUnmock("@capacitor/core");
    vi.resetModules();
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("resolves the id so the sign-in request itself carries the header", async () => {
    vi.stubGlobal("fetch", fetchOk());
    const { ensureInstallationForAuth, getInstallationIdSync } = await loadNative();

    const result = await ensureInstallationForAuth();

    expect(result.installationId).toBeTruthy();
    expect(getInstallationIdSync()).toBe(result.installationId);
  });

  it("returns instead of blocking login when the backend never answers", async () => {
    vi.useFakeTimers();
    // A register that hangs forever: login must not wait on it.
    vi.stubGlobal("fetch", vi.fn(() => new Promise(() => undefined)));
    const { ensureInstallationForAuth } = await loadNative();

    const pending = ensureInstallationForAuth();
    await vi.advanceTimersByTimeAsync(2_500);
    const result = await pending;

    expect(result.remoteRegistered).toBe(false);
    vi.useRealTimers();
  });

  it("does not block on web either", async () => {
    vi.stubGlobal("fetch", fetchOk());
    const { ensureInstallationForAuth } = await loadWeb();

    const result = await ensureInstallationForAuth();

    expect(result.failureCode).toBe("unsupported");
  });
});

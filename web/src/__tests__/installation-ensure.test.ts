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

// The register contract (Api::V1::App::InstallationsController): only a body
// that claims "registered" means the row exists. A 202 is a 2xx that wrote
// nothing, so it must never be cached as a success.
function fetchOk() {
  return vi.fn(async () => ({
    ok: true,
    status: 200,
    statusText: "OK",
    json: async () => ({ status: "registered", registered: true, installation_id: "x", created: true }),
  }));
}

function fetchDeferred() {
  return vi.fn(async () => ({
    ok: true,
    status: 202,
    statusText: "Accepted",
    json: async () => ({ status: "deferred", registered: false, retryable: true }),
  }));
}

function fetchDisabled() {
  return vi.fn(async () => ({
    ok: true,
    status: 202,
    statusText: "Accepted",
    json: async () => ({ status: "disabled", registered: false, retryable: false }),
  }));
}

// A backend that predates the contract: success echoed the id, 202 had no body.
function fetchLegacyOk() {
  return vi.fn(async () => ({
    ok: true,
    status: 201,
    statusText: "Created",
    json: async () => ({ installation_id: "x", created: true }),
  }));
}

function fetchStatus(status: number) {
  return vi.fn(async () => ({
    ok: false,
    status,
    statusText: "Error",
    json: async () => ({ error: "nope" }),
  }));
}

// A native load whose durable store only answers after `delayMs`. The local id
// must still be resolved from it — the network budget is a separate leg.
async function loadNativeWithSlowStore(delayMs: number, value: string | null = "stored-id") {
  vi.resetModules();
  vi.doMock("@capacitor/core", () => nativeCapacitor());
  vi.doMock("@capacitor/preferences", () => ({
    Preferences: {
      get: vi.fn(() => new Promise((resolve) => setTimeout(() => resolve({ value }), delayMs))),
      set: vi.fn(async () => undefined),
    },
  }));
  return await import("@/shared/lib/analytics/installation");
}

function registerCalls(mock: ReturnType<typeof fetchOk>): unknown[] {
  return mock.mock.calls.filter((call) => String(call[0]).includes(REGISTER_PATH));
}

function headersOf(call: unknown): Record<string, string> {
  const [ , init ] = call as [string, RequestInit];
  return (init?.headers ?? {}) as Record<string, string>;
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
    vi.stubGlobal("fetch", fetchOk());
    // The durable native store is the source of truth, not the mirror.
    const { ensureInstallationRegistered } = await loadNativeWithSlowStore(0, "existing-id");

    const result = await ensureInstallationRegistered();

    expect(result.installationId).toBe("existing-id");
  });

  // A restored Android backup brings the WebView data dir back (localStorage
  // included) but NOT the Capacitor store, which is excluded from backup. An id
  // that exists only in the mirror therefore belongs to the PREVIOUS
  // installation and adopting it is what produced link_result=conflict.
  it("does not adopt a mirror-only id on native (restored backup)", async () => {
    window.localStorage.setItem("eh_installation_id", "restored-id");
    vi.stubGlobal("fetch", fetchOk());
    const { ensureInstallationRegistered } = await loadNativeWithSlowStore(0, null);

    const result = await ensureInstallationRegistered();

    expect(result.installationId).not.toBe("restored-id");
    expect(result.installationId).toBeTruthy();
    // The stale mirror is overwritten, so nothing reads it back later.
    expect(window.localStorage.getItem("eh_installation_id")).toBe(result.installationId);
  });

  it("keeps using the localStorage id on web, where there is no native store", async () => {
    window.localStorage.setItem("eh_installation_id", "web-id");
    vi.stubGlobal("fetch", fetchOk());
    const { getInstallationId } = await loadWeb();

    expect(await getInstallationId()).toBe("web-id");
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

  it("does not call a 202 deferred a registration", async () => {
    const fetchMock = fetchDeferred();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadNative();

    const result = await ensureInstallationRegistered();

    // The row was NOT written: claiming success here is what used to suppress
    // every retry for the rest of the app cycle.
    expect(result.remoteRegistered).toBe(false);
    expect(result.remoteStatus).toBe("deferred");
    expect(result.failureCode).toBe("deferred");
    expect(result.installationId).toBeTruthy();
    // Accepted-but-not-stored is not retried inside the same call: the next
    // cycle (resume/auth) is the retry.
    expect(registerCalls(fetchMock)).toHaveLength(1);
  });

  it("really POSTs again on a later call after a deferred", async () => {
    const fetchMock = fetchDeferred();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadNative();

    await ensureInstallationRegistered();
    await ensureInstallationRegistered();

    expect(registerCalls(fetchMock)).toHaveLength(2);
  });

  it("keeps the local id after a deferred so the header still goes out", async () => {
    vi.stubGlobal("fetch", fetchDeferred());
    const { ensureInstallationRegistered, getInstallationIdSync } = await loadNative();

    const result = await ensureInstallationRegistered();

    expect(getInstallationIdSync()).toBe(result.installationId);
    expect(window.localStorage.getItem("eh_installation_id")).toBe(result.installationId);
  });

  it("stops POSTing when the backend says the feature is disabled, without claiming success", async () => {
    const fetchMock = fetchDisabled();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadNative();

    const first = await ensureInstallationRegistered();
    const second = await ensureInstallationRegistered();

    expect(first.remoteRegistered).toBe(false);
    expect(first.remoteStatus).toBe("disabled");
    expect(second.remoteRegistered).toBe(false);
    expect(second.remoteStatus).toBe("disabled");
    // Not retryable: a disabled backend answers the same forever.
    expect(registerCalls(fetchMock)).toHaveLength(1);
  });

  it("does not re-send a payload the backend already rejected (422)", async () => {
    const fetchMock = fetchStatus(422);
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadNative();

    const first = await ensureInstallationRegistered();
    const second = await ensureInstallationRegistered();

    expect(first.failureCode).toBe("client_error");
    expect(second.failureCode).toBe("client_error");
    expect(second.remoteRegistered).toBe(false);
    // Identical metadata would be rejected identically.
    expect(registerCalls(fetchMock)).toHaveLength(1);
  });

  it("retries a 429 like a transient failure, not like a bad payload", async () => {
    const fetchMock = fetchStatus(429);
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadNative();

    const result = await ensureInstallationRegistered();

    expect(result.failureCode).toBe("transient");
    expect(registerCalls(fetchMock)).toHaveLength(2);
  });

  it("accepts a success body from a backend that predates the contract", async () => {
    const fetchMock = fetchLegacyOk();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationRegistered } = await loadNative();

    const result = await ensureInstallationRegistered();

    expect(result.remoteRegistered).toBe(true);
    expect(result.remoteStatus).toBe("registered");
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
    vi.doUnmock("@capacitor/preferences");
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
    // The store is mocked so this test isolates ONE variable: the network. With
    // the real plugin the dynamic import itself is pending work that fake timers
    // never drive, which has nothing to do with what is being asserted here.
    const { ensureInstallationForAuth } = await loadNativeWithSlowStore(0, "stored-id");
    vi.useFakeTimers();
    // A register that hangs forever: login must not wait on it.
    vi.stubGlobal("fetch", vi.fn(() => new Promise(() => undefined)));

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

  // The timeout exists for the NETWORK. A slow durable store used to eat the
  // whole budget and let the first login go out with no X-Installation-Id.
  it("still resolves the local id when the durable store is slow", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("fetch", vi.fn(() => new Promise(() => undefined))); // register hangs
    const { ensureInstallationForAuth } = await loadNativeWithSlowStore(1_200);

    const pending = ensureInstallationForAuth();
    await vi.advanceTimersByTimeAsync(1_200); // store answers
    await vi.advanceTimersByTimeAsync(2_000); // then the remote budget expires
    const result = await pending;

    // The id came from the store, and the remote leg — and only it — timed out.
    expect(result.installationId).toBe("stored-id");
    expect(result.remoteRegistered).toBe(false);
    expect(result.remoteStatus).toBe("deferred");
  });

  it("puts the header on the auth request even when the store was slow", async () => {
    vi.useFakeTimers();
    const fetchMock = vi.fn(async (url: string) =>
      String(url).includes(REGISTER_PATH)
        ? await new Promise(() => undefined) // register never answers
        : { ok: true, status: 200, statusText: "OK", json: async () => ({ id: 1 }) }
    );
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationForAuth } = await loadNativeWithSlowStore(1_200);
    const { api } = await import("@/shared/lib/api");

    const pending = ensureInstallationForAuth();
    await vi.advanceTimersByTimeAsync(3_500);
    const result = await pending;

    await api.post("/api/v1/auth/sign_in", { email: "a@b.c", password: "x" });

    const signIn = fetchMock.mock.calls.find((call) => String(call[0]).includes("/auth/sign_in"));
    expect(headersOf(signIn)["X-Installation-Id"]).toBe(result.installationId);
  });

  it("never blocks login when the local store hangs forever", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("fetch", fetchOk());
    // A native plugin that never answers: the mirror/new id takes over.
    const { ensureInstallationForAuth } = await loadNativeWithSlowStore(10 * 60_000);

    const pending = ensureInstallationForAuth();
    await vi.advanceTimersByTimeAsync(6_000);
    const result = await pending;

    expect(result.installationId).toBeTruthy();
  });

  it("gives concurrent auth callers the same id and one register", async () => {
    const fetchMock = fetchOk();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationForAuth } = await loadNative();

    const results = await Promise.all([
      ensureInstallationForAuth(),
      ensureInstallationForAuth(),
      ensureInstallationForAuth(),
    ]);

    expect(new Set(results.map((r) => r.installationId)).size).toBe(1);
    expect(registerCalls(fetchMock)).toHaveLength(1);
  });

  it("reports a 202 as not registered, so auth proceeds and the retry survives", async () => {
    const fetchMock = fetchDeferred();
    vi.stubGlobal("fetch", fetchMock);
    const { ensureInstallationForAuth } = await loadNative();

    const result = await ensureInstallationForAuth();

    expect(result.installationId).toBeTruthy();
    expect(result.remoteRegistered).toBe(false);
    expect(result.remoteStatus).toBe("deferred");
  });
});

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const store = new Map<string, string>();

// O token vive no Keychain via nativeSessionStorage — nunca em Preferences ou
// localStorage. Ver native-session-storage.test.ts para o contrato completo.
vi.mock("@/shared/lib/native-session-storage", () => ({
  nativeSessionStorage: {
    get: vi.fn(async (key: string) => store.get(key) ?? null),
    set: vi.fn(async (key: string, value: string) => {
      store.set(key, value);
    }),
    remove: vi.fn(async (key: string) => {
      store.delete(key);
    }),
  },
}));

const FLAG = "NEXT_PUBLIC_NATIVE_LOCAL_BUNDLE";

async function loadModule(localBundle: boolean) {
  vi.resetModules();
  if (localBundle) process.env[FLAG] = "true";
  else delete process.env[FLAG];
  return import("@/shared/lib/mobile-session");
}

beforeEach(() => store.clear());
afterEach(() => {
  delete process.env[FLAG];
});

describe("mobile session token — native local bundle", () => {
  it("stores and reads back a token", async () => {
    const m = await loadModule(true);

    await m.storeMobileSessionToken("ehs_abc");

    expect(m.getCachedMobileSessionToken()).toBe("ehs_abc");
  });

  it("primes the in-memory cache from persisted storage", async () => {
    store.set("eh_mobile_session", "ehs_persisted");
    const m = await loadModule(true);

    // api.ts reads synchronously, so nothing is available before priming.
    expect(m.getCachedMobileSessionToken()).toBeNull();
    await m.primeMobileSessionToken();
    expect(m.getCachedMobileSessionToken()).toBe("ehs_persisted");
  });

  it("captures the token out of a login response", async () => {
    const m = await loadModule(true);

    await m.captureMobileSessionToken({ id: 1, mobile_session_token: "ehs_login" });

    expect(m.getCachedMobileSessionToken()).toBe("ehs_login");
  });

  it("ignores a login response without a token", async () => {
    const m = await loadModule(true);

    await m.captureMobileSessionToken({ id: 1 });

    expect(m.getCachedMobileSessionToken()).toBeNull();
  });

  it("clears memory and storage on sign out", async () => {
    const m = await loadModule(true);
    await m.storeMobileSessionToken("ehs_abc");

    await m.clearMobileSessionToken();

    expect(m.getCachedMobileSessionToken()).toBeNull();
    expect(store.has("eh_mobile_session")).toBe(false);
  });

  it("sends the opt-in issue header", async () => {
    const m = await loadModule(true);

    expect(m.mobileSessionIssueHeader()).toEqual({ "X-EasyHealth-Mobile-Session": "1" });
  });
});

// O shell remoto do Android carrega easyhealth.art e é same-site com a API, então
// o cookie funciona e um bearer token ali seria superfície de XSS sem ganho.
describe("mobile session token — web and remote Android shell", () => {
  it("never caches a token", async () => {
    const m = await loadModule(false);

    await m.storeMobileSessionToken("ehs_abc");
    await m.captureMobileSessionToken({ mobile_session_token: "ehs_abc" });

    expect(m.getCachedMobileSessionToken()).toBeNull();
  });

  it("never writes to persistent storage", async () => {
    const m = await loadModule(false);

    await m.storeMobileSessionToken("ehs_abc");

    expect(store.size).toBe(0);
  });

  it("sends no opt-in header, so the server issues nothing", async () => {
    const m = await loadModule(false);

    expect(m.mobileSessionIssueHeader()).toEqual({});
  });

  it("priming is a no-op even when storage has a stale value", async () => {
    store.set("eh_mobile_session", "ehs_stale");
    const m = await loadModule(false);

    await m.primeMobileSessionToken();

    expect(m.getCachedMobileSessionToken()).toBeNull();
  });
});

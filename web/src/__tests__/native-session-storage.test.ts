import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Contrato de armazenamento: o bearer token é credencial e só pode ir para o
// Keychain. Estes testes existem para que um "fallback conveniente" para
// localStorage não consiga entrar despercebido depois.

const keychain = new Map<string, string>();
const calls = { get: 0, set: 0, remove: 0 };

vi.mock("@capacitor/core", () => ({
  registerPlugin: () => ({
    get: async ({ key }: { key: string }) => {
      calls.get++;
      return { value: keychain.get(key) ?? null };
    },
    set: async ({ key, value }: { key: string; value: string }) => {
      calls.set++;
      keychain.set(key, value);
    },
    remove: async ({ key }: { key: string }) => {
      calls.remove++;
      keychain.delete(key);
    },
  }),
}));

const FLAG = "NEXT_PUBLIC_NATIVE_LOCAL_BUNDLE";

async function loadSession(localBundle: boolean) {
  vi.resetModules();
  if (localBundle) process.env[FLAG] = "true";
  else delete process.env[FLAG];
  return import("@/shared/lib/mobile-session");
}

beforeEach(() => {
  keychain.clear();
  calls.get = calls.set = calls.remove = 0;
  localStorage.clear();
  sessionStorage.clear();
});

afterEach(() => {
  delete process.env[FLAG];
});

describe("secure storage contract", () => {
  it("persists the token through the secure storage abstraction", async () => {
    const m = await loadSession(true);

    await m.storeMobileSessionToken("ehs_secret");

    expect(calls.set).toBe(1);
    expect(keychain.get("eh_mobile_session")).toBe("ehs_secret");
  });

  it("NEVER writes the token to localStorage or sessionStorage", async () => {
    const m = await loadSession(true);

    await m.storeMobileSessionToken("ehs_secret");

    const dumped = JSON.stringify({ ...localStorage, ...sessionStorage });
    expect(dumped).not.toContain("ehs_secret");
    expect(localStorage.length).toBe(0);
    expect(sessionStorage.length).toBe(0);
  });

  it("bootstraps through secure storage, not through web storage", async () => {
    keychain.set("eh_mobile_session", "ehs_from_keychain");
    const m = await loadSession(true);

    await m.primeMobileSessionToken();

    expect(calls.get).toBe(1);
    expect(m.getCachedMobileSessionToken()).toBe("ehs_from_keychain");
  });

  it("calls secure remove on logout", async () => {
    const m = await loadSession(true);
    await m.storeMobileSessionToken("ehs_secret");

    await m.clearMobileSessionToken();

    expect(calls.remove).toBe(1);
    expect(keychain.size).toBe(0);
    expect(m.getCachedMobileSessionToken()).toBeNull();
  });

  it("keeps the stored token when a Keychain read fails", async () => {
    keychain.set("eh_mobile_session", "ehs_secret");
    const m = await loadSession(true);
    const storage = await import("@/shared/lib/native-session-storage");
    vi.spyOn(storage.nativeSessionStorage, "get").mockRejectedValueOnce(new Error("locked"));

    await m.primeMobileSessionToken();

    // Sem token em memória o app pede login — mas o que estava gravado
    // continua lá para a próxima tentativa.
    expect(m.getCachedMobileSessionToken()).toBeNull();
    expect(keychain.get("eh_mobile_session")).toBe("ehs_secret");
  });

  it("touches no storage at all outside the native bundle", async () => {
    const m = await loadSession(false);

    await m.storeMobileSessionToken("ehs_secret");
    await m.primeMobileSessionToken();

    expect(calls.set).toBe(0);
    expect(calls.get).toBe(0);
    expect(localStorage.length).toBe(0);
  });
});

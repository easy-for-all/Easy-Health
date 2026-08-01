import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// Installation identity: which events keep the installation_id and which ones
// must mint a new one.
//
// The bug this file guards: Android Auto Backup restored the app's data on
// reinstall, the client adopted the restored installation_id, and the backend —
// correctly — refused to move an installation owned by user A to user B
// (link_result=conflict). The new account was created with no AppInstallation.
//
// The rule now: the Capacitor store is excluded from backup, so an id found
// there was created by THIS installation. The localStorage mirror is NOT a read
// source on native, because the WebView data dir IS backed up.

const REGISTER_PATH = "/api/v1/app/installations/register";
const PREF_ID = "eh_installation_id";
const PREF_LINKED = "eh_installation_linked";
const PREF_REGENERATED = "eh_installation_regenerated";

function nativeCapacitor() {
  return { Capacitor: { getPlatform: () => "android", isNativePlatform: () => true } };
}

// A stand-in for SharedPreferences "CapacitorStorage". Kept across module
// reloads to model an app restart, and dropped to model a reinstall.
function makeStore(initial: Record<string, string> = {}) {
  const data: Record<string, string> = { ...initial };
  return {
    data,
    factory: () => ({
      Preferences: {
        get: vi.fn(async ({ key }: { key: string }) => ({ value: data[key] ?? null })),
        set: vi.fn(async ({ key, value }: { key: string; value: string }) => {
          data[key] = value;
        }),
        remove: vi.fn(async ({ key }: { key: string }) => {
          delete data[key];
        }),
      },
    }),
  };
}

// A store the plugin never answers for (missing plugin / hung bridge).
function unreachableStoreFactory() {
  return {
    Preferences: {
      get: vi.fn(() => Promise.reject(new Error("plugin unavailable"))),
      set: vi.fn(() => Promise.reject(new Error("plugin unavailable"))),
    },
  };
}

async function bootNative(storeFactory: () => unknown) {
  vi.resetModules();
  vi.doMock("@capacitor/core", () => nativeCapacitor());
  vi.doMock("@capacitor/preferences", storeFactory);
  return await import("@/shared/lib/analytics/installation");
}

function registerResponse(linkStatus: string | null) {
  return {
    ok: true,
    status: 200,
    statusText: "OK",
    json: async () => ({
      status: "registered",
      registered: true,
      installation_id: "echo",
      created: false,
      link_status: linkStatus,
    }),
  };
}

// Answers each register call with the next link_status in the queue.
function fetchWithLinkStatuses(...statuses: (string | null)[]) {
  const queue = [...statuses];
  return vi.fn(async (url: string) => {
    if (!String(url).includes(REGISTER_PATH)) {
      return { ok: true, status: 200, statusText: "OK", json: async () => ({}) };
    }
    return registerResponse(queue.shift() ?? null);
  });
}

function registerBodies(mock: ReturnType<typeof fetchWithLinkStatuses>): Record<string, unknown>[] {
  return mock.mock.calls
    .filter((call) => String(call[0]).includes(REGISTER_PATH))
    .map((call) => JSON.parse(String((call[1] as RequestInit)?.body)));
}

describe("installation identity across install, update and restore", () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.stubGlobal("fetch", fetchWithLinkStatuses("linked"));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.doUnmock("@capacitor/core");
    vi.doUnmock("@capacitor/preferences");
    vi.resetModules();
    vi.restoreAllMocks();
  });

  it("keeps the installation_id across an app update", async () => {
    const store = makeStore();
    const first = await bootNative(store.factory);
    const original = await first.getInstallationId();

    // An update replaces the APK; the data dir (and the store) is untouched.
    const afterUpdate = await bootNative(store.factory);

    expect(await afterUpdate.getInstallationId()).toBe(original);
  });

  it("keeps the installation_id across logout and login", async () => {
    const store = makeStore();
    const mod = await bootNative(store.factory);
    const original = await mod.getInstallationId();

    // Logout drops the user_id (what resetIdentity does); the installation is
    // not a user and must survive it, including across the reload that follows.
    const { setUserId } = await import("@/shared/lib/analytics/context");
    setUserId(undefined);

    expect(await mod.getInstallationId()).toBe(original);
  });

  it("mints a new installation_id on a real reinstall", async () => {
    const store = makeStore();
    const first = await bootNative(store.factory);
    const original = await first.getInstallationId();

    // Uninstall wipes the whole data dir: store and WebView storage.
    const wiped = makeStore();
    window.localStorage.clear();
    const reinstalled = await bootNative(wiped.factory);

    expect(await reinstalled.getInstallationId()).not.toBe(original);
  });

  it("does not reuse a restored id when the store has no marker for it", async () => {
    const first = await bootNative(makeStore().factory);
    const original = await first.getInstallationId();
    expect(window.localStorage.getItem(PREF_ID)).toBe(original);

    // Restore: the WebView data dir comes back (mirror included), the Capacitor
    // store does not — it is excluded from backup.
    const restored = makeStore();
    const reinstalled = await bootNative(restored.factory);
    const fresh = await reinstalled.getInstallationId();

    expect(fresh).not.toBe(original);
    expect(restored.data[PREF_ID]).toBe(fresh);
    // The stale mirror is overwritten so nothing can read it back.
    expect(window.localStorage.getItem(PREF_ID)).toBe(fresh);
  });

  it("drops the rest of the restored analytics identity with the old id", async () => {
    window.localStorage.setItem(PREF_ID, "restored-id");
    window.localStorage.setItem("eh_anon_id", "restored-anon");
    window.localStorage.setItem("eh_installed", "2026-01-01T00:00:00.000Z");

    const mod = await bootNative(makeStore().factory);
    await mod.getInstallationId();

    // Otherwise the restored device keeps reporting as the previous one and
    // never emits app_first_open.
    expect(window.localStorage.getItem("eh_anon_id")).toBeNull();
    expect(window.localStorage.getItem("eh_installed")).toBeNull();
  });

  it("does not mint a new id when the store is merely unreachable", async () => {
    window.localStorage.setItem(PREF_ID, "known-id");

    const mod = await bootNative(unreachableStoreFactory);

    // "No answer" is not "empty": minting here would churn a new installation
    // on every boot that meets a slow bridge.
    expect(await mod.getInstallationId()).toBe("known-id");
  });
});

describe("recovery from a link conflict", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.doUnmock("@capacitor/core");
    vi.doUnmock("@capacitor/preferences");
    vi.resetModules();
    vi.restoreAllMocks();
  });

  it("regenerates the id when the conflicting installation was never linked here", async () => {
    // The state of a device that restored a backup: the store carries an id
    // that belongs to another user, and no link was ever recorded for it.
    const store = makeStore({ [PREF_ID]: "f64c22e7-restored" });
    const fetchMock = fetchWithLinkStatuses("conflict", "linked");
    vi.stubGlobal("fetch", fetchMock);

    const mod = await bootNative(store.factory);
    const result = await mod.ensureInstallationRegistered();

    const bodies = registerBodies(fetchMock);
    expect(bodies).toHaveLength(2);
    expect(bodies[0].installation_id).toBe("f64c22e7-restored");
    expect(bodies[1].installation_id).not.toBe("f64c22e7-restored");
    // The new id is the one the app keeps and reports.
    expect(result.installationId).toBe(bodies[1].installation_id);
    expect(store.data[PREF_ID]).toBe(bodies[1].installation_id);
    expect(result.remoteRegistered).toBe(true);
  });

  it("keeps the regenerated id on the next boot", async () => {
    const store = makeStore({ [PREF_ID]: "restored-id" });
    vi.stubGlobal("fetch", fetchWithLinkStatuses("conflict", "linked"));
    const mod = await bootNative(store.factory);
    const result = await mod.ensureInstallationRegistered();

    vi.stubGlobal("fetch", fetchWithLinkStatuses("already_linked"));
    const rebooted = await bootNative(store.factory);

    expect(await rebooted.getInstallationId()).toBe(result.installationId);
  });

  it("does NOT regenerate on a legitimate account switch", async () => {
    // This installation linked successfully before, so the id is genuinely
    // ours: a conflict here means a second user is signing in on this device.
    // The backend must keep the original owner and the client must not shop for
    // a new identity.
    const store = makeStore({
      [PREF_ID]: "owned-id",
      [PREF_LINKED]: "2026-07-01T00:00:00.000Z",
    });
    const fetchMock = fetchWithLinkStatuses("conflict");
    vi.stubGlobal("fetch", fetchMock);

    const mod = await bootNative(store.factory);
    const result = await mod.ensureInstallationRegistered();

    // The invariant is that no OTHER id is ever registered: a regeneration would
    // show up here as a second call carrying a brand new installation_id.
    const registered = registerBodies(fetchMock).map((body) => body.installation_id);
    expect(registered.filter((id) => id !== "owned-id")).toEqual([]);
    expect(result.installationId).toBe("owned-id");
    expect(store.data[PREF_ID]).toBe("owned-id");
    expect(store.data[PREF_REGENERATED]).toBeUndefined();
  });

  it("records the successful link so a later conflict is treated as a switch", async () => {
    const store = makeStore({ [PREF_ID]: "owned-id" });
    vi.stubGlobal("fetch", fetchWithLinkStatuses("linked"));

    const mod = await bootNative(store.factory);
    await mod.ensureInstallationRegistered();

    expect(store.data[PREF_LINKED]).toBeTruthy();
  });

  it("recovers at most once per installation", async () => {
    const store = makeStore({ [PREF_ID]: "restored-id" });
    vi.stubGlobal("fetch", fetchWithLinkStatuses("conflict", "conflict"));
    const first = await bootNative(store.factory);
    await first.ensureInstallationRegistered();
    const afterFirst = store.data[PREF_ID];
    expect(store.data[PREF_REGENERATED]).toBeTruthy();

    // A later boot that conflicts again must not keep minting installations.
    const secondFetch = fetchWithLinkStatuses("conflict");
    vi.stubGlobal("fetch", secondFetch);
    const second = await bootNative(store.factory);
    await second.ensureInstallationRegistered();

    expect(registerBodies(secondFetch)).toHaveLength(1);
    expect(store.data[PREF_ID]).toBe(afterFirst);
  });

  it("does not regenerate when the store cannot prove anything", async () => {
    // No store, no evidence: leave the id alone rather than guess.
    const fetchMock = fetchWithLinkStatuses("conflict");
    vi.stubGlobal("fetch", fetchMock);

    const mod = await bootNative(unreachableStoreFactory);
    await mod.ensureInstallationRegistered();

    expect(registerBodies(fetchMock)).toHaveLength(1);
  });
});

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// installation_id lifecycle on the web/PWA path (jsdom is not a native shell, so
// the @capacitor/preferences branch is skipped and the localStorage mirror is
// the store). Native persistence is covered by the release checklist on a device.

async function loadInstallation() {
  // Fresh module state per test so "reinstall" (cleared storage) is realistic.
  vi.resetModules();
  vi.doMock("@capacitor/core", () => ({
    Capacitor: { getPlatform: () => "web", isNativePlatform: () => false },
  }));
  return await import("@/shared/lib/analytics/installation");
}

describe("installation_id", () => {
  beforeEach(() => {
    window.localStorage.clear();
    window.sessionStorage.clear();
  });

  afterEach(() => {
    vi.doUnmock("@capacitor/core");
    vi.resetModules();
    vi.restoreAllMocks();
  });

  it("creates a UUID once and returns it stably across calls", async () => {
    const { getInstallationId } = await loadInstallation();
    const a = await getInstallationId();
    const b = await getInstallationId();
    expect(a).toBe(b);
    expect(a).toMatch(/[0-9a-f-]{8,}/i);
    expect(window.localStorage.getItem("eh_installation_id")).toBe(a);
  });

  it("never generates two ids under concurrent boot calls", async () => {
    const { getInstallationId } = await loadInstallation();
    const [a, b, c] = await Promise.all([
      getInstallationId(),
      getInstallationId(),
      getInstallationId(),
    ]);
    expect(a).toBe(b);
    expect(b).toBe(c);
  });

  it("reuses a previously persisted id (survives a fresh module load / logout)", async () => {
    const first = await loadInstallation();
    const original = await first.getInstallationId();

    // Simulate a new app session (module state gone) but storage intact.
    const second = await loadInstallation();
    expect(await second.getInstallationId()).toBe(original);
  });

  it("creates a NEW id after a reinstall (storage wiped)", async () => {
    const first = await loadInstallation();
    const original = await first.getInstallationId();

    window.localStorage.clear(); // reinstall wipes storage
    const second = await loadInstallation();
    const fresh = await second.getInstallationId();
    expect(fresh).not.toBe(original);
  });

  it("does not call the backend off-native: web/PWA carries no installation", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response("{}", { status: 200 })
    );
    const { ensureInstallationRegistered } = await loadInstallation();

    const result = await ensureInstallationRegistered();

    expect(result.remoteRegistered).toBe(false);
    expect(result.failureCode).toBe("unsupported");
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});

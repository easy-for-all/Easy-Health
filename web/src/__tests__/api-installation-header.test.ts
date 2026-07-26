import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// X-Installation-Id must ride on every request the central api client makes, so
// the backend can re-link the installation to the signed-in user (Marco 1/3).
// context.ts caches the id in memory, so each test reloads the modules to get a
// clean cache and drives the value through the localStorage mirror.

const HEADER = "X-Installation-Id";

async function loadApi() {
  vi.resetModules();
  return await import("@/shared/lib/api");
}

function okFetch() {
  return vi.fn(async () => ({ ok: true, status: 200, statusText: "OK", json: async () => ({}) }));
}

function headersOf(fetchMock: ReturnType<typeof okFetch>): Record<string, string> {
  const init = fetchMock.mock.calls[0][1] as RequestInit | undefined;
  return (init?.headers ?? {}) as Record<string, string>;
}

describe("api installation header", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("sends the header on JSON requests when the id is cached", async () => {
    window.localStorage.setItem("eh_installation_id", "inst-abc");
    const fetchMock = okFetch();
    vi.stubGlobal("fetch", fetchMock);

    const { api } = await loadApi();
    await api.get("/api/v1/auth/me");

    const headers = headersOf(fetchMock);
    expect(headers[HEADER]).toBe("inst-abc");
    expect(headers["Content-Type"]).toBe("application/json");
  });

  it("sends the header on the native Google sign-in POST", async () => {
    window.localStorage.setItem("eh_installation_id", "inst-google");
    const fetchMock = okFetch();
    vi.stubGlobal("fetch", fetchMock);

    const { api } = await loadApi();
    await api.post("/api/v1/auth/google/native", { id_token: "jwt", platform: "android" });

    expect(headersOf(fetchMock)[HEADER]).toBe("inst-google");
  });

  it("sends the header on multipart uploads without forcing a Content-Type", async () => {
    window.localStorage.setItem("eh_installation_id", "inst-upload");
    const fetchMock = okFetch();
    vi.stubGlobal("fetch", fetchMock);

    const { api } = await loadApi();
    await api.uploadPost("/api/v1/user_media", new FormData());

    const headers = headersOf(fetchMock);
    expect(headers[HEADER]).toBe("inst-upload");
    expect(headers["Content-Type"]).toBeUndefined();
  });

  it("omits the header when no id has been resolved yet", async () => {
    const fetchMock = okFetch();
    vi.stubGlobal("fetch", fetchMock);

    const { api } = await loadApi();
    await api.get("/api/v1/auth/me");

    const headers = headersOf(fetchMock);
    expect(headers[HEADER]).toBeUndefined();
    expect(headers["Content-Type"]).toBe("application/json");
  });
});

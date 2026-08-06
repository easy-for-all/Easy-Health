import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  ensureAnonymousSession,
  currentAnonymousToken,
  clearAnonymousSession,
} from "@/features/anonymous/anonymous-session";
import { claimAnonymousData, hasPendingClaim } from "@/features/anonymous/claim";

const { mockIsNativeApp, mockInstallationId, mockApiPost, mockTrackEvent } = vi.hoisted(() => ({
  mockIsNativeApp: vi.fn(() => true),
  mockInstallationId: vi.fn<() => string | undefined>(() => "install-1"),
  mockApiPost: vi.fn(),
  mockTrackEvent: vi.fn(),
}));

vi.mock("@/shared/lib/analytics/context", () => ({
  isNativeApp: () => mockIsNativeApp(),
  getCachedInstallationId: () => mockInstallationId(),
  getAnalyticsContext: () => ({ platform: "android", build_number: "60", app_version: "1.0" }),
}));

vi.mock("@/shared/lib/analytics/installation", () => ({
  getInstallationId: () => Promise.resolve(mockInstallationId() ?? ""),
}));

vi.mock("@/shared/lib/analytics", () => ({ trackEvent: mockTrackEvent }));
vi.mock("@/shared/lib/api", () => ({
  api: { post: mockApiPost },
  ApiError: class extends Error {},
}));

function mintResponse(overrides: Record<string, unknown> = {}) {
  return {
    ok: true,
    json: () =>
      Promise.resolve({
        token: "eh_anon.signed",
        expires_at: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
        plans_remaining: 3,
        ...overrides,
      }),
  };
}

describe("anonymous session token", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    mockIsNativeApp.mockReturnValue(true);
    mockInstallationId.mockReturnValue("install-1");
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(mintResponse())));
  });

  // O fetch stubado vaza para outros arquivos que compartilham o mesmo worker
  // se não for desfeito aqui.
  afterEach(() => vi.unstubAllGlobals());

  // Web e PWA não têm modo anônimo. Pedir um token ali criaria a expectativa de
  // um fluxo que o backend vai recusar de todo jeito.
  it("never mints outside the native app", async () => {
    mockIsNativeApp.mockReturnValue(false);

    expect(await ensureAnonymousSession()).toBeNull();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("mints once and reuses the stored token", async () => {
    expect(await ensureAnonymousSession()).toBe("eh_anon.signed");
    expect(await ensureAnonymousSession()).toBe("eh_anon.signed");

    expect(fetch).toHaveBeenCalledTimes(1);
  });

  // O diretório do WebView entra no Android Auto Backup, então um restore pode
  // devolver o token da instalação anterior. Ele seria recusado pelo servidor
  // com installation_mismatch; descartar antes evita a viagem.
  it("discards a token that belongs to another installation", async () => {
    await ensureAnonymousSession();
    mockInstallationId.mockReturnValue("install-2");

    expect(currentAnonymousToken()).toBeNull();
    await ensureAnonymousSession();
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("renews a token that is about to expire", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() => Promise.resolve(mintResponse({ expires_at: new Date(Date.now() + 60_000).toISOString() })))
    );

    await ensureAnonymousSession();
    await ensureAnonymousSession();

    // Um token que vence no meio de uma geração de 90s desperdiçaria uma das
    // três vagas da pessoa.
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("falls back to no session when the backend refuses", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() => Promise.resolve({ ok: false, json: () => Promise.resolve({ error: "anonymous_session_rejected" }) }))
    );

    expect(await ensureAnonymousSession()).toBeNull();
    expect(currentAnonymousToken()).toBeNull();
  });
});

describe("claiming anonymous data after sign-up", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    mockIsNativeApp.mockReturnValue(true);
    mockInstallationId.mockReturnValue("install-1");
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(mintResponse())));
  });

  afterEach(() => vi.unstubAllGlobals());

  it("is a no-op without an anonymous session", async () => {
    expect(await claimAnonymousData()).toBe("nothing_to_claim");
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("claims and clears the token, which the backend stops accepting", async () => {
    await ensureAnonymousSession();
    mockApiPost.mockResolvedValue({ status: "claimed", plans_claimed: 1, sessions_claimed: 2 });

    expect(await claimAnonymousData()).toBe("claimed");
    expect(mockApiPost).toHaveBeenCalledWith("/api/v1/anonymous/claim", { anonymous_token: "eh_anon.signed" });
    expect(currentAnonymousToken()).toBeNull();
    expect(hasPendingClaim()).toBe(false);
    expect(mockTrackEvent).toHaveBeenCalledWith(
      "anonymous_workouts_claim_succeeded",
      expect.objectContaining({ plans_claimed: 1, sessions_claimed: 2 })
    );
  });

  // Um claim perdido é DADO perdido — plano e treinos que a pessoa já fez —,
  // diferente de um evento perdido. Por isso o marcador sobrevive à falha.
  it("keeps a marker so a failed claim is retried on the next boot", async () => {
    await ensureAnonymousSession();
    mockApiPost.mockRejectedValue(new Error("offline"));

    expect(await claimAnonymousData()).toBe("failed");
    expect(hasPendingClaim()).toBe(true);
    expect(currentAnonymousToken()).toBe("eh_anon.signed");
  });

  // Conflito é permanente: o aparelho é de outra conta e repetir dá o mesmo
  // resultado. Manter o marcador faria o app tentar para sempre.
  it("stops retrying on a conflict", async () => {
    await ensureAnonymousSession();
    mockApiPost.mockResolvedValue({ status: "conflict" });

    expect(await claimAnonymousData()).toBe("conflict");
    expect(hasPendingClaim()).toBe(false);
    expect(currentAnonymousToken()).toBeNull();
    expect(mockTrackEvent).toHaveBeenCalledWith("anonymous_workouts_claim_failed", { reason: "conflict" });
  });

  it("carries no personal data in the claim events", async () => {
    await ensureAnonymousSession();
    mockApiPost.mockResolvedValue({ status: "claimed", plans_claimed: 1, sessions_claimed: 0 });
    await claimAnonymousData();

    const [, props] = mockTrackEvent.mock.calls[0];
    expect(Object.keys(props as object).sort()).toEqual(["plans_claimed", "sessions_claimed"]);
  });

  it("clears a stale session when there is nothing to claim", async () => {
    clearAnonymousSession();

    expect(await claimAnonymousData()).toBe("nothing_to_claim");
    expect(hasPendingClaim()).toBe(false);
  });
});

import { render, waitFor } from "@testing-library/react";
import { describe, expect, it, vi, beforeEach } from "vitest";
import { AuthProvider } from "@/features/auth/auth-context";

// Bootstrap da sessão no shell nativo.
//
// A regra que mais importa aqui: 401 != offline. Um 401 significa que o token
// morreu e precisa sair do Keychain; uma falha de rede significa que o servidor
// não foi alcançado, e apagar o token nesse caso deslogaria o usuário toda vez
// que o metrô entrasse num túnel.

const MockApiError = vi.hoisted(
  () =>
    class ApiError extends Error {
      status: number;
      constructor(message: string, status: number) {
        super(message);
        this.name = "ApiError";
        this.status = status;
      }
    }
);

const apiGet = vi.hoisted(() => vi.fn());
const apiDelete = vi.hoisted(() => vi.fn());
const primeMobileSessionToken = vi.hoisted(() => vi.fn(async () => undefined));
const clearMobileSessionToken = vi.hoisted(() => vi.fn(async () => undefined));
const captureMobileSessionToken = vi.hoisted(() => vi.fn(async () => undefined));

vi.mock("@capacitor/core", () => ({
  Capacitor: { isNativePlatform: () => true, getPlatform: () => "ios" },
}));

vi.mock("@/shared/lib/api", () => ({
  api: { get: apiGet, delete: apiDelete, post: vi.fn() },
  ApiError: MockApiError,
  TRIAL_EXPIRED_EVENT: "app:trial_expired",
}));

vi.mock("@/shared/lib/mobile-session", () => ({
  primeMobileSessionToken,
  clearMobileSessionToken,
  captureMobileSessionToken,
  getCachedMobileSessionToken: () => null,
  mobileSessionIssueHeader: () => ({}),
  usesMobileSessionAuth: () => true,
}));

vi.mock("@/shared/lib/analytics", () => ({
  identifyUser: vi.fn(),
  resetIdentity: vi.fn(),
}));
vi.mock("@/shared/lib/analytics/installation", () => ({
  ensureInstallationForAuth: vi.fn(async () => ({})),
}));
vi.mock("@/shared/lib/analytics/context", () => ({ isNativeApp: () => true }));
vi.mock("@/features/anonymous/claim", () => ({ claimAnonymousData: vi.fn() }));
vi.mock("@/shared/lib/pushNotifications", () => ({
  syncPushIfGranted: vi.fn(async () => undefined),
}));

beforeEach(() => {
  vi.clearAllMocks();
  apiDelete.mockResolvedValue(undefined);
});

function renderProvider() {
  return render(
    <AuthProvider>
      <div>ok</div>
    </AuthProvider>
  );
}

describe("native auth bootstrap", () => {
  it("loads the token from secure storage before the first request", async () => {
    apiGet.mockResolvedValue({ id: 1 });

    renderProvider();

    await waitFor(() => expect(apiGet).toHaveBeenCalled());
    // Sem isto, api.ts montaria o primeiro header sem Authorization e o app
    // abriria sempre deslogado.
    expect(primeMobileSessionToken).toHaveBeenCalled();
    const primeOrder = primeMobileSessionToken.mock.invocationCallOrder[0];
    const getOrder = apiGet.mock.invocationCallOrder[0];
    expect(primeOrder).toBeLessThan(getOrder);
  });

  it("keeps the session when the request succeeds", async () => {
    apiGet.mockResolvedValue({ id: 1 });

    renderProvider();

    await waitFor(() => expect(apiGet).toHaveBeenCalled());
    expect(clearMobileSessionToken).not.toHaveBeenCalled();
  });

  it("clears the stored token on 401", async () => {
    apiGet.mockRejectedValue(new MockApiError("unauthorized", 401));

    renderProvider();

    await waitFor(() => expect(clearMobileSessionToken).toHaveBeenCalled());
  });

  it("clears the stored token on 403", async () => {
    apiGet.mockRejectedValue(new MockApiError("forbidden", 403));

    renderProvider();

    await waitFor(() => expect(clearMobileSessionToken).toHaveBeenCalled());
  });

  // O teste que impede o bug de "o app me desloga no elevador".
  it("does NOT clear the token on a network failure", async () => {
    apiGet.mockRejectedValue(new TypeError("Failed to fetch"));

    renderProvider();

    await waitFor(() => expect(apiGet).toHaveBeenCalled());
    await new Promise((r) => setTimeout(r, 20));
    expect(clearMobileSessionToken).not.toHaveBeenCalled();
  });

  it("does NOT clear the token on a 500", async () => {
    apiGet.mockRejectedValue(new MockApiError("boom", 500));

    renderProvider();

    await waitFor(() => expect(apiGet).toHaveBeenCalled());
    await new Promise((r) => setTimeout(r, 20));
    expect(clearMobileSessionToken).not.toHaveBeenCalled();
  });
});

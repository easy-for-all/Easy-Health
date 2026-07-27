import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  GoogleAuthError,
  classifyGoogleAuthError,
  googleAuthWebUrl,
  postGoogleNative,
  startGoogleAuth,
} from "@/shared/lib/googleAuth";

const { mockPost, mockGetInstallationId, mockEnsureInstallationForAuth } = vi.hoisted(() => ({
  mockPost: vi.fn(),
  mockGetInstallationId: vi.fn(),
  mockEnsureInstallationForAuth: vi.fn(),
}));

vi.mock("@/shared/lib/api", () => ({ api: { post: mockPost } }));
vi.mock("@/shared/lib/analytics/installation", () => ({
  getInstallationId: mockGetInstallationId,
  ensureInstallationForAuth: mockEnsureInstallationForAuth,
}));

const assign = vi.fn();

beforeEach(() => {
  vi.clearAllMocks();
  mockGetInstallationId.mockResolvedValue("installation-1");
  mockEnsureInstallationForAuth.mockResolvedValue({
    installationId: "installation-1",
    remoteRegistered: true,
  });
  mockPost.mockResolvedValue({ id: 1, new_user: true });
  Object.defineProperty(window, "location", { value: { assign, replace: vi.fn() }, writable: true });
});

describe("startGoogleAuth — web branch", () => {
  it("navigates explicitly instead of relying on a link", async () => {
    const outcome = await startGoogleAuth({ native: false });

    expect(outcome).toEqual({ navigated: true });
    expect(assign).toHaveBeenCalledTimes(1);
    expect(assign.mock.calls[0][0]).toContain("/auth/google/web");
  });

  it("carries the accepted consent into the OmniAuth entry point", async () => {
    await startGoogleAuth({
      native: false,
      consent: { termsAccepted: true, privacyAccepted: true, marketingConsent: true },
    });

    const url = new URL(assign.mock.calls[0][0]);
    expect(url.searchParams.get("terms_accepted")).toBe("1");
    expect(url.searchParams.get("privacy_accepted")).toBe("1");
    expect(url.searchParams.get("marketing_consent")).toBe("1");
  });

  it("never turns an unchecked marketing box into an opt-in", async () => {
    await startGoogleAuth({
      native: false,
      consent: { termsAccepted: true, privacyAccepted: true, marketingConsent: false },
    });

    expect(new URL(assign.mock.calls[0][0]).searchParams.get("marketing_consent")).toBe("0");
  });

  it("sends no consent at all when the caller has none (login screen)", () => {
    expect(googleAuthWebUrl()).not.toContain("terms_accepted");
  });
});

describe("postGoogleNative payload", () => {
  // The whole point of resolving the installation here is that the sign-in
  // request itself carries X-Installation-Id, so the backend can link inside
  // this very cycle instead of waiting for a later authenticated request.
  it("resolves the installation BEFORE exchanging the token", async () => {
    const order: string[] = [];
    mockEnsureInstallationForAuth.mockImplementation(async () => {
      order.push("installation");
      return { installationId: "installation-1", remoteRegistered: true };
    });
    mockPost.mockImplementation(async () => {
      order.push("exchange");
      return { id: 1, new_user: true };
    });

    await postGoogleNative("id-token");

    expect(order).toEqual([ "installation", "exchange" ]);
  });

  it("still exchanges the token when the installation is unavailable", async () => {
    mockEnsureInstallationForAuth.mockResolvedValue({
      installationId: null,
      remoteRegistered: false,
      failureCode: "transient",
    });

    await expect(postGoogleNative("id-token")).resolves.toMatchObject({
      redirectPath: "/onboarding",
    });
  });

  it("omits the consent fields entirely when none was collected", async () => {
    await postGoogleNative("id-token");

    expect(mockPost).toHaveBeenCalledWith(
      "/api/v1/auth/google/native",
      { id_token: "id-token", platform: "android" },
    );
  });

  it("sends the real consent values, including a declined marketing flag", async () => {
    await postGoogleNative("id-token", {
      termsAccepted: true,
      privacyAccepted: true,
      marketingConsent: false,
    });

    expect(mockPost).toHaveBeenCalledWith("/api/v1/auth/google/native", {
      id_token: "id-token",
      platform: "android",
      terms_accepted: true,
      privacy_accepted: true,
      marketing_consent: false,
    });
  });
});

describe("classifyGoogleAuthError", () => {
  it.each([
    ["consent_required", "consent_required"],
    ["account_deleted", "account_deleted"],
    ["invalid_token", "invalid_token"],
    ["exchange_failed", "network"],
    ["plugin_init_failed", "unknown"],
  ])("maps the %s code to %s", (code, expected) => {
    expect(classifyGoogleAuthError(new GoogleAuthError("boom", code))).toBe(expected);
  });

  it("recognises a dismissed account picker so it is not reported as a failure", () => {
    expect(classifyGoogleAuthError(new GoogleAuthError("boom", "12501"))).toBe("cancelled");
    expect(classifyGoogleAuthError(new GoogleAuthError("The user canceled the sign-in flow", "x")))
      .toBe("cancelled");
  });
});

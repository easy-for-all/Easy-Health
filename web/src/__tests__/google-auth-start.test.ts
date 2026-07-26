import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  GoogleAuthError,
  classifyGoogleAuthError,
  googleAuthWebUrl,
  postGoogleNative,
  startGoogleAuth,
} from "@/shared/lib/googleAuth";

const { mockPost, mockGetInstallationId } = vi.hoisted(() => ({
  mockPost: vi.fn(),
  mockGetInstallationId: vi.fn(),
}));

vi.mock("@/shared/lib/api", () => ({ api: { post: mockPost } }));
vi.mock("@/shared/lib/analytics/installation", () => ({
  getInstallationId: mockGetInstallationId,
}));

const assign = vi.fn();

beforeEach(() => {
  vi.clearAllMocks();
  mockGetInstallationId.mockResolvedValue("installation-1");
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

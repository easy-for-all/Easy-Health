import { api } from "@/shared/lib/api";
import {
  exchangeMobileAuthCallback,
  parseMobileAuthCallback,
  type MobileAuthUser,
} from "@/shared/lib/mobileAuth";

vi.mock("@/shared/lib/api", () => ({
  api: {
    post: vi.fn(),
  },
}));

const postMock = vi.mocked(api.post);

describe("mobileAuth", () => {
  beforeEach(() => {
    postMock.mockReset();
  });

  it("parses the HTTPS App Link callback", () => {
    const parsed = parseMobileAuthCallback("https://easyhealth.art/mobile-auth/callback?code=abc&platform=android");

    expect(parsed).toMatchObject({
      type: "code",
      code: "abc",
      platform: "android",
    });
  });

  it("parses the custom scheme fallback", () => {
    const parsed = parseMobileAuthCallback("easyhealth://auth/callback?code=abc&platform=android");

    expect(parsed).toMatchObject({
      type: "code",
      code: "abc",
      platform: "android",
    });
  });

  it("recognizes legacy callbacks without exchanging their token", () => {
    const parsed = parseMobileAuthCallback("easyhealth://auth-callback?token=old-token");

    expect(parsed).toMatchObject({
      type: "legacy-token",
      token: "old-token",
      platform: "android",
    });
  });

  it("parses OAuth error callbacks", () => {
    const parsed = parseMobileAuthCallback("https://easyhealth.art/mobile-auth/callback?error=oauth_failed");

    expect(parsed).toMatchObject({
      type: "error",
      error: "oauth_failed",
      platform: "android",
    });
  });

  it("ignores unrelated URLs", () => {
    expect(parseMobileAuthCallback("https://example.com/mobile-auth/callback?code=abc")).toBeNull();
    expect(parseMobileAuthCallback("easyhealth://profile")).toBeNull();
  });

  it("exchanges a code and returns the expected redirect", async () => {
    const user: MobileAuthUser = {
      id: 1,
      name: "Test User",
      email: "test@example.com",
      created_at: "2026-07-09T12:00:00Z",
      new_user: true,
    };
    postMock.mockResolvedValue(user);

    const parsed = parseMobileAuthCallback("easyhealth://auth/callback?code=abc&platform=android");
    if (!parsed) throw new Error("Expected callback to parse");

    const result = await exchangeMobileAuthCallback(parsed);

    expect(postMock).toHaveBeenCalledWith("/api/v1/auth/mobile/exchange", {
      code: "abc",
      platform: "android",
    });
    expect(result).toEqual({ user, redirectPath: "/onboarding" });
  });
});

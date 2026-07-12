import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import SignUpPage from "@/app/sign-up/page";

const {
  mockIsNative,
  mockNativeSignIn,
  mockPostGoogleNative,
  mockGoogleAuthWebUrl,
  mockAuthLog,
  mockSignUp,
  mockPush,
} = vi.hoisted(() => ({
  mockIsNative: vi.fn(() => false),
  mockNativeSignIn: vi.fn(),
  mockPostGoogleNative: vi.fn(),
  mockGoogleAuthWebUrl: vi.fn(() => "https://api.test/auth/google/web?terms_accepted=1"),
  mockAuthLog: vi.fn(),
  mockSignUp: vi.fn(),
  mockPush: vi.fn(),
}));

vi.mock("@capacitor/core", () => ({
  Capacitor: { isNativePlatform: () => mockIsNative() },
}));

vi.mock("@/shared/lib/googleAuth", () => ({
  googleAuthWebUrl: mockGoogleAuthWebUrl,
  GoogleAuthError: class GoogleAuthError extends Error {},
  authLog: mockAuthLog,
  nativeGoogleSignIn: mockNativeSignIn,
  postGoogleNative: mockPostGoogleNative,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
  useSearchParams: () => new URLSearchParams(),
}));

vi.mock("@/features/auth/auth-context", () => ({
  useAuth: () => ({ signUp: mockSignUp }),
}));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: vi.fn(),
  trackConversion: vi.fn(),
  trackCheckoutStarted: vi.fn(),
  EVENTS: { SIGNUP_STARTED: "signup_started", SIGNUP_COMPLETED: "signup_completed" },
  CONVERSIONS: { SIGNUP: "signup" },
}));

vi.mock("@/shared/lib/api", () => ({
  api: { post: vi.fn() },
  ApiError: class ApiError extends Error {},
}));

vi.mock("@/features/billing/checkout-intent", () => ({
  getPendingPlan: () => null,
  clearPendingPlan: vi.fn(),
}));

function googleButton() {
  return screen.getByText("Continuar com Google").closest("a") as HTMLAnchorElement;
}

function consentCheckbox() {
  // First checkbox in the form is the Terms + Privacy consent.
  return screen.getByRole("checkbox", { name: /Termos de Uso/i });
}

describe("SignUp consent gate for Google sign-in", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsNative.mockReturnValue(false);
    mockNativeSignIn.mockResolvedValue("id-token");
    mockPostGoogleNative.mockResolvedValue({ redirectPath: "/onboarding" });
    Object.defineProperty(window, "location", {
      value: { replace: vi.fn(), href: "" },
      writable: true,
    });
  });

  it("blocks Google when nothing is checked (web): no native call, no navigation, warning shown", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(googleButton());

    expect(mockNativeSignIn).not.toHaveBeenCalled();
    expect(mockPostGoogleNative).not.toHaveBeenCalled();
    expect(screen.getByText("Aceite os termos para continuar")).toBeInTheDocument();
    expect(mockAuthLog).toHaveBeenCalledWith(
      "auth_blocked_missing_consent",
      expect.objectContaining({ provider: "google", surface: "signup" }),
    );
  });

  it("does not expose a navigable href on the Google button while consent is missing (web)", () => {
    render(<SignUpPage />);
    expect(googleButton().getAttribute("href")).toBeNull();
  });

  it("blocks the native handler even when the click fires (direct bypass guard)", async () => {
    mockIsNative.mockReturnValue(true);
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(googleButton());

    expect(mockNativeSignIn).not.toHaveBeenCalled();
    expect(screen.getByText("Aceite os termos para continuar")).toBeInTheDocument();
  });

  it("does not enter the Google loading state without consent", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(googleButton());

    expect(screen.getByText("Continuar com Google")).toBeInTheDocument();
    expect(screen.queryByText("Entrando com Google...")).not.toBeInTheDocument();
  });

  it("runs the native Google flow exactly once when consent is accepted", async () => {
    mockIsNative.mockReturnValue(true);
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());
    await user.click(googleButton());

    await waitFor(() => expect(mockNativeSignIn).toHaveBeenCalledTimes(1));
    expect(mockPostGoogleNative).toHaveBeenCalledTimes(1);
    expect(mockPostGoogleNative).toHaveBeenCalledWith(
      "id-token",
      expect.objectContaining({ termsAccepted: true, privacyAccepted: true }),
    );
  });

  it("exposes the consent-carrying web URL once consent is accepted", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());

    expect(googleButton().getAttribute("href")).toBe(
      "https://api.test/auth/google/web?terms_accepted=1",
    );
  });

  it("keeps the email/password flow working (calls signUp) once consent is accepted", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.type(screen.getByPlaceholderText("Seu nome"), "Marcus");
    await user.type(screen.getByPlaceholderText("seu@email.com"), "marcus@test.com");
    await user.type(screen.getByPlaceholderText("Mínimo 8 caracteres"), "supersecret");
    await user.click(consentCheckbox());
    await user.click(screen.getByRole("button", { name: "Criar conta" }));

    await waitFor(() => expect(mockSignUp).toHaveBeenCalledTimes(1));
    expect(mockSignUp).toHaveBeenCalledWith("Marcus", "marcus@test.com", "supersecret", false);
    expect(mockNativeSignIn).not.toHaveBeenCalled();
  });
});

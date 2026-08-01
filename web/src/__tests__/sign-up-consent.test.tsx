import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import SignUpPage from "@/app/sign-up/page";

const {
  mockIsNative,
  mockIsHydrated,
  mockStartGoogleAuth,
  mockClassify,
  mockAuthLog,
  mockSignUp,
  mockPush,
  mockSearchParams,
} = vi.hoisted(() => ({
  mockIsNative: vi.fn(() => false),
  mockIsHydrated: vi.fn(() => true),
  mockStartGoogleAuth: vi.fn(),
  mockClassify: vi.fn(() => "unknown"),
  mockAuthLog: vi.fn(),
  mockSignUp: vi.fn(),
  mockPush: vi.fn(),
  mockSearchParams: vi.fn(() => new URLSearchParams()),
}));

vi.mock("@/shared/lib/platform", () => ({
  useIsNativePlatform: () => mockIsNative(),
  useIsHydrated: () => mockIsHydrated(),
}));

vi.mock("@/shared/lib/googleAuth", () => ({
  GoogleAuthError: class GoogleAuthError extends Error {},
  authLog: mockAuthLog,
  startGoogleAuth: mockStartGoogleAuth,
  classifyGoogleAuthError: mockClassify,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
  useSearchParams: () => mockSearchParams(),
}));

vi.mock("@/features/auth/auth-context", () => ({
  useAuth: () => ({ signUp: mockSignUp }),
}));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: vi.fn(),
  trackOnce: vi.fn(),
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
  // The label swaps to "Carregando..." while the page is not hydrated yet.
  return screen.getByRole("button", { name: /Google|Carregando/i });
}

function consentCheckbox() {
  // First checkbox in the form is the Terms + Privacy consent.
  return screen.getByRole("checkbox", { name: /Termos de Uso/i });
}

describe("SignUp consent gate for Google sign-in", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsNative.mockReturnValue(false);
    mockIsHydrated.mockReturnValue(true);
    mockClassify.mockReturnValue("unknown");
    mockSearchParams.mockReturnValue(new URLSearchParams());
    mockStartGoogleAuth.mockResolvedValue({ navigated: false, redirectPath: "/onboarding" });
    Object.defineProperty(window, "location", {
      value: { replace: vi.fn(), assign: vi.fn(), href: "" },
      writable: true,
    });
  });

  it("blocks Google when nothing is checked (web): no auth call, no navigation, warning shown", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(googleButton());

    expect(mockStartGoogleAuth).not.toHaveBeenCalled();
    expect(screen.getByText("Aceite os termos para continuar")).toBeInTheDocument();
    expect(mockAuthLog).toHaveBeenCalledWith(
      "auth_blocked_missing_consent",
      expect.objectContaining({ provider: "google", surface: "signup" }),
    );
  });

  it("exposes no OAuth link at all — the CTA is a button, never an <a href>", () => {
    render(<SignUpPage />);

    expect(googleButton().tagName).toBe("BUTTON");
    expect(googleButton()).not.toHaveAttribute("href");
    expect(document.querySelector('a[href*="auth/google"]')).toBeNull();
  });

  it("keeps the button inert until React has hydrated", () => {
    mockIsHydrated.mockReturnValue(false);
    render(<SignUpPage />);

    expect(googleButton()).toBeDisabled();
  });

  it("blocks the native handler even when the click fires (direct bypass guard)", async () => {
    mockIsNative.mockReturnValue(true);
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(googleButton());

    expect(mockStartGoogleAuth).not.toHaveBeenCalled();
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

    await waitFor(() => expect(mockStartGoogleAuth).toHaveBeenCalledTimes(1));
    expect(mockStartGoogleAuth).toHaveBeenCalledWith({
      native: true,
      consent: expect.objectContaining({ termsAccepted: true, privacyAccepted: true }),
    });
  });

  it("hands the browser to the OmniAuth flow carrying the accepted consent", async () => {
    mockStartGoogleAuth.mockResolvedValue({ navigated: true });
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());
    await user.click(googleButton());

    await waitFor(() =>
      expect(mockStartGoogleAuth).toHaveBeenCalledWith({
        native: false,
        consent: { termsAccepted: true, privacyAccepted: true, marketingConsent: false },
      }),
    );
  });

  it("passes the marketing choice through instead of assuming an opt-in", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());
    await user.click(screen.getByRole("checkbox", { name: /dicas personalizadas/i }));
    await user.click(googleButton());

    await waitFor(() =>
      expect(mockStartGoogleAuth).toHaveBeenCalledWith(
        expect.objectContaining({ consent: expect.objectContaining({ marketingConsent: true }) }),
      ),
    );
  });

  it("starts the flow only once on a double click", async () => {
    mockIsNative.mockReturnValue(true);
    mockStartGoogleAuth.mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve({ navigated: true }), 20)),
    );
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());
    const button = googleButton();
    await user.click(button);
    await user.click(button);

    expect(mockStartGoogleAuth).toHaveBeenCalledTimes(1);
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
    expect(mockStartGoogleAuth).not.toHaveBeenCalled();
  });
});

describe("SignUp arriving from the login screen's Google CTA", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsNative.mockReturnValue(false);
    mockIsHydrated.mockReturnValue(true);
    mockStartGoogleAuth.mockResolvedValue({ navigated: true });
    Object.defineProperty(window, "location", {
      value: { replace: vi.fn(), assign: vi.fn(), href: "" },
      writable: true,
    });
  });

  it("explains why the user landed here without pre-accepting anything", () => {
    mockSearchParams.mockReturnValue(new URLSearchParams("provider=google"));
    render(<SignUpPage />);

    expect(screen.getByText(/ainda não está cadastrada/i)).toBeInTheDocument();
    expect(consentCheckbox()).not.toBeChecked();
  });

  it("never starts OAuth on its own from provider=google", () => {
    mockSearchParams.mockReturnValue(new URLSearchParams("provider=google"));
    render(<SignUpPage />);

    expect(mockStartGoogleAuth).not.toHaveBeenCalled();
  });

  it("tells the user what to do after a refused consent, checkbox still unchecked", () => {
    mockSearchParams.mockReturnValue(new URLSearchParams("error=consent_required&provider=google"));
    render(<SignUpPage />);

    expect(screen.getByText(/aceite os Termos de Uso e a Política de Privacidade abaixo/i))
      .toBeInTheDocument();
    expect(consentCheckbox()).not.toBeChecked();
    expect(mockStartGoogleAuth).not.toHaveBeenCalled();
  });
});

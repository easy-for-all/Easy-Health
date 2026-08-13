import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import SignUpPage from "@/app/sign-up/page";

const {
  mockIsNative,
  mockIsHydrated,
  mockStartGoogleAuth,
  mockDescribe,
  mockAuthLog,
  mockTrackEvent,
  mockSignUp,
  mockPush,
  mockSearchParams,
} = vi.hoisted(() => ({
  mockIsNative: vi.fn(() => false),
  mockIsHydrated: vi.fn(() => true),
  mockStartGoogleAuth: vi.fn(),
  mockDescribe: vi.fn(),
  mockAuthLog: vi.fn(),
  mockTrackEvent: vi.fn(),
  mockSignUp: vi.fn(),
  mockPush: vi.fn(),
  mockSearchParams: vi.fn(() => new URLSearchParams()),
}));

// The shape describeGoogleAuthError returns, so each test states an outcome
// rather than a code the classifier then has to be trusted to read correctly.
function outcome(
  failure: string,
  category: string,
  errorCode = "boom",
  reachedBackend = false,
) {
  return { failure, category, errorCode, reachedBackend };
}

vi.mock("@/shared/lib/platform", () => ({
  useIsNativePlatform: () => mockIsNative(),
  useIsHydrated: () => mockIsHydrated(),
}));

vi.mock("@/shared/lib/googleAuth", () => ({
  GoogleAuthError: class GoogleAuthError extends Error {},
  authLog: mockAuthLog,
  startGoogleAuth: mockStartGoogleAuth,
  describeGoogleAuthError: mockDescribe,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
  useSearchParams: () => mockSearchParams(),
}));

vi.mock("@/features/auth/auth-context", () => ({
  useAuth: () => ({ signUp: mockSignUp }),
}));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: mockTrackEvent,
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

// O aviso que importa é o que fica acima do botão do Google: com o formulário de
// e-mail recolhido por padrão, ele é o único visível quando o toque é bloqueado.
function consentWarning() {
  return screen.getByRole("alert");
}

// O e-mail é a rota secundária desta tela e só monta sob demanda.
async function openEmailForm(user: ReturnType<typeof userEvent.setup>) {
  await user.click(screen.getByRole("button", { name: /criar com e-mail/i }));
}

describe("SignUp consent gate for Google sign-in", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsNative.mockReturnValue(false);
    mockIsHydrated.mockReturnValue(true);
    mockDescribe.mockReturnValue(outcome("unknown", "unknown"));
    mockSearchParams.mockReturnValue(new URLSearchParams());
    mockStartGoogleAuth.mockResolvedValue({ navigated: false, redirectPath: "/onboarding", newUser: true });
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
    expect(mockTrackEvent).toHaveBeenCalledWith("auth_provider_clicked", {
      provider: "google",
      auth_screen: "sign_up",
      intent: "sign_up",
      terms_accepted: false,
      source: "auth_screen",
      auth_attempt_id: expect.any(String),
    });
    expect(mockTrackEvent).not.toHaveBeenCalledWith(
      "social_login_started",
      expect.objectContaining({ provider: "google" }),
    );
    expect(consentWarning()).toBeInTheDocument();
    expect(mockAuthLog).toHaveBeenCalledWith(
      "auth_blocked_missing_consent",
      expect.objectContaining({ provider: "google", surface: "signup" }),
    );
    // O bloqueio precisa ser contável no funil, não só no console: sem este evento
    // um toque barrado e um toque que nunca aconteceu ficam idênticos nos dados.
    expect(mockTrackEvent).toHaveBeenCalledWith("auth_consent_blocked", {
      provider: "google",
      auth_screen: "sign_up",
      auth_attempt_id: expect.any(String),
    });
  });

  // O motivo desta tela existir assim: o aceite ficava ~400px abaixo do botão do
  // Google, então o toque na ação principal era barrado por uma caixa que a pessoa
  // nunca tinha rolado até ver, e o botão parecia simplesmente morto.
  it("puts the consent checkbox before the Google button in the document", () => {
    render(<SignUpPage />);

    const position = consentCheckbox().compareDocumentPosition(googleButton());
    expect(position & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("collapses the email form so consent and Google fit one phone screen", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    expect(screen.queryByPlaceholderText("Seu nome")).not.toBeInTheDocument();

    await openEmailForm(user);

    expect(screen.getByPlaceholderText("Seu nome")).toBeInTheDocument();
    expect(consentCheckbox()).toBeInTheDocument();
  });

  it("counts a blocked email submit too, not only the Google one", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await openEmailForm(user);
    await user.type(screen.getByPlaceholderText("Seu nome"), "Marcus");
    await user.type(screen.getByPlaceholderText("seu@email.com"), "marcus@test.com");
    await user.type(screen.getByPlaceholderText("Mínimo 8 caracteres"), "supersecret");
    await user.click(screen.getByRole("button", { name: "Criar conta" }));

    expect(mockSignUp).not.toHaveBeenCalled();
    expect(mockTrackEvent).toHaveBeenCalledWith("auth_consent_blocked", {
      provider: "email",
      auth_screen: "sign_up",
      auth_attempt_id: expect.any(String),
    });
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
    expect(consentWarning()).toBeInTheDocument();
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
    expect(mockTrackEvent).toHaveBeenCalledWith("auth_provider_clicked", {
      provider: "google",
      auth_screen: "sign_up",
      intent: "sign_up",
      terms_accepted: true,
      source: "auth_screen",
      auth_attempt_id: expect.any(String),
    });
    const clickedIndex = mockTrackEvent.mock.calls.findIndex(([name]) => name === "auth_provider_clicked");
    const startedIndex = mockTrackEvent.mock.calls.findIndex(([name]) => name === "social_login_started");
    expect(startedIndex).toBeGreaterThan(clickedIndex);
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
    expect(mockTrackEvent.mock.calls.filter(([name]) => name === "auth_provider_clicked")).toHaveLength(1);
  });

  it("keeps the email/password flow working (calls signUp) once consent is accepted", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await openEmailForm(user);
    await user.type(screen.getByPlaceholderText("Seu nome"), "Marcus");
    await user.type(screen.getByPlaceholderText("seu@email.com"), "marcus@test.com");
    await user.type(screen.getByPlaceholderText("Mínimo 8 caracteres"), "supersecret");
    await user.click(consentCheckbox());
    await user.click(screen.getByRole("button", { name: "Criar conta" }));

    await waitFor(() => expect(mockSignUp).toHaveBeenCalledTimes(1));
    expect(mockTrackEvent).toHaveBeenCalledWith("auth_provider_clicked", {
      provider: "email",
      auth_screen: "sign_up",
      intent: "sign_up",
      terms_accepted: true,
      source: "auth_screen",
      auth_attempt_id: expect.any(String),
    });
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

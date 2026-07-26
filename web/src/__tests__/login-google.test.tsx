import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, it, expect, vi, beforeEach } from "vitest";
import LoginPage from "@/app/login/page";
import messages from "../../messages/pt-BR.json";

const {
  mockIsNative,
  mockIsHydrated,
  mockStartGoogleAuth,
  mockClassify,
  mockAuthLog,
  mockSignIn,
  mockPush,
} = vi.hoisted(() => ({
  mockIsNative: vi.fn(() => false),
  mockIsHydrated: vi.fn(() => true),
  mockStartGoogleAuth: vi.fn(),
  mockClassify: vi.fn(() => "unknown"),
  mockAuthLog: vi.fn(),
  mockSignIn: vi.fn(),
  mockPush: vi.fn(),
}));

vi.mock("@/shared/lib/platform", () => ({
  useIsNativePlatform: () => mockIsNative(),
  useIsHydrated: () => mockIsHydrated(),
}));

vi.mock("@/shared/lib/googleAuth", () => ({
  GoogleAuthError: class GoogleAuthError extends Error {
    code: string;
    constructor(message: string, code = "x") {
      super(message);
      this.code = code;
    }
  },
  authLog: mockAuthLog,
  startGoogleAuth: mockStartGoogleAuth,
  classifyGoogleAuthError: mockClassify,
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) =>
    (messages.auth as Record<string, string>)[key] ?? `MISSING:${key}`,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
  useSearchParams: () => new URLSearchParams(),
}));

vi.mock("next/link", () => ({
  default: ({ href, children, ...rest }: { href: string; children: React.ReactNode }) => (
    <a href={href} {...rest}>{children}</a>
  ),
}));

vi.mock("@/features/auth/auth-context", () => ({ useAuth: () => ({ signIn: mockSignIn }) }));
vi.mock("@/shared/lib/api", () => ({
  api: { post: vi.fn() },
  ApiError: class ApiError extends Error {},
}));
vi.mock("@/features/billing/checkout-intent", () => ({
  getPendingPlan: () => null,
  clearPendingPlan: vi.fn(),
}));
vi.mock("@/shared/lib/analytics", () => ({ trackCheckoutStarted: vi.fn() }));

function googleButton() {
  // The label swaps to "Carregando..." while the page is not hydrated yet.
  return screen.getByRole("button", { name: /Google|Carregando/i });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockIsNative.mockReturnValue(false);
  mockIsHydrated.mockReturnValue(true);
  mockClassify.mockReturnValue("unknown");
  mockStartGoogleAuth.mockResolvedValue({ navigated: false, redirectPath: "/dashboard" });
  Object.defineProperty(window, "location", {
    value: { replace: vi.fn(), assign: vi.fn(), href: "" },
    writable: true,
  });
});

describe("Login screen — no OAuth link before hydration", () => {
  it("renders no working /auth/google/web link in the server-rendered markup", () => {
    mockIsHydrated.mockReturnValue(false);

    const html = renderToStaticMarkup(<LoginPage />);

    expect(html).not.toContain("/auth/google/web");
    expect(html).not.toMatch(/<a[^>]+href="[^"]*auth\/google/);
  });

  it("uses a button, not an anchor, for the Google CTA", () => {
    render(<LoginPage />);

    expect(googleButton().tagName).toBe("BUTTON");
    expect(googleButton()).not.toHaveAttribute("href");
  });

  it("keeps the button inert until React has hydrated", () => {
    mockIsHydrated.mockReturnValue(false);
    render(<LoginPage />);

    expect(googleButton()).toBeDisabled();
    expect(screen.getByText(messages.auth.loadingButton)).toBeInTheDocument();
  });
});

describe("Login screen — Google flows", () => {
  it("runs the native flow without any sign-up consent", async () => {
    mockIsNative.mockReturnValue(true);
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(mockStartGoogleAuth).toHaveBeenCalledTimes(1));
    expect(mockStartGoogleAuth).toHaveBeenCalledWith({ native: true });
    await waitFor(() => expect(window.location.replace).toHaveBeenCalledWith("/dashboard"));
  });

  it("hands the web browser to the server-side OmniAuth flow", async () => {
    mockStartGoogleAuth.mockResolvedValue({ navigated: true });
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(mockStartGoogleAuth).toHaveBeenCalledWith({ native: false }));
    expect(window.location.replace).not.toHaveBeenCalled();
  });

  it("starts the flow only once on a double click", async () => {
    mockIsNative.mockReturnValue(true);
    mockStartGoogleAuth.mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve({ navigated: true }), 20)),
    );
    const user = userEvent.setup();
    render(<LoginPage />);

    const button = googleButton();
    await user.click(button);
    await user.click(button);

    expect(mockStartGoogleAuth).toHaveBeenCalledTimes(1);
  });
});

describe("Login screen — unregistered Google account", () => {
  beforeEach(() => {
    mockIsNative.mockReturnValue(true);
    mockClassify.mockReturnValue("consent_required");
    mockStartGoogleAuth.mockRejectedValue(new Error("consent"));
  });

  it("explains the account does not exist and offers the sign-up route", async () => {
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() =>
      expect(screen.getByText(messages.auth.googleAccountNotRegistered)).toBeInTheDocument(),
    );
    const cta = screen.getByRole("link", { name: messages.auth.createAccountWithGoogle });
    expect(cta).toHaveAttribute("href", "/sign-up?provider=google");
  });

  it("leaves the button usable again instead of stuck in loading", async () => {
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(googleButton()).not.toBeDisabled());
    expect(screen.getByText(messages.auth.continueWithGoogle)).toBeInTheDocument();
  });

  it("does not create an account from the login screen", async () => {
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(mockStartGoogleAuth).toHaveBeenCalledWith({ native: true }));
    expect(mockStartGoogleAuth).not.toHaveBeenCalledWith(
      expect.objectContaining({ consent: expect.anything() }),
    );
  });
});

describe("Login screen — other Google outcomes", () => {
  beforeEach(() => {
    mockIsNative.mockReturnValue(true);
    mockStartGoogleAuth.mockRejectedValue(new Error("boom"));
  });

  it("stays silent when the user dismissed the account picker", async () => {
    mockClassify.mockReturnValue("cancelled");
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(googleButton()).not.toBeDisabled());
    expect(screen.queryByText(messages.auth.oauthError)).not.toBeInTheDocument();
    expect(screen.queryByText(messages.auth.googleAccountNotRegistered)).not.toBeInTheDocument();
  });

  it("reports a connectivity failure distinctly from a generic error", async () => {
    mockClassify.mockReturnValue("network");
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(screen.getByText(messages.auth.networkError)).toBeInTheDocument());
  });
});

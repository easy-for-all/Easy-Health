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
  mockDescribe,
  mockAuthLog,
  mockTrackEvent,
  mockTrackOnce,
  mockSignIn,
  mockPush,
} = vi.hoisted(() => ({
  mockIsNative: vi.fn(() => false),
  mockIsHydrated: vi.fn(() => true),
  mockStartGoogleAuth: vi.fn(),
  mockDescribe: vi.fn(),
  mockAuthLog: vi.fn(),
  mockTrackEvent: vi.fn(),
  mockTrackOnce: vi.fn(),
  mockSignIn: vi.fn(),
  mockPush: vi.fn(),
}));

// The shape describeGoogleAuthError returns, so each test states an outcome
// instead of a code the classifier then has to be trusted to read correctly.
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
  GoogleAuthError: class GoogleAuthError extends Error {
    code: string;
    constructor(message: string, code = "x") {
      super(message);
      this.code = code;
    }
  },
  authLog: mockAuthLog,
  startGoogleAuth: mockStartGoogleAuth,
  describeGoogleAuthError: mockDescribe,
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
vi.mock("@/shared/lib/analytics", () => ({
  trackCheckoutStarted: vi.fn(),
  trackEvent: mockTrackEvent,
  // trackOnce guards the terminal events; the real key-based dedupe is asserted
  // through this spy so a rerender cannot quietly double a conversion.
  trackOnce: mockTrackOnce,
}));

// Every event of one attempt must carry the same id, and a retry must not reuse
// it. Both are read off the emitted payloads.
function eventsNamed(name: string) {
  return mockTrackEvent.mock.calls.filter(([eventName]) => eventName === name);
}

function attemptIdOf(name: string): string | undefined {
  const [, payload] = eventsNamed(name)[0] ?? [];
  return (payload as Record<string, string> | undefined)?.auth_attempt_id;
}

function googleButton() {
  // The label swaps to "Carregando..." while the page is not hydrated yet.
  return screen.getByRole("button", { name: /Google|Carregando/i });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockIsNative.mockReturnValue(false);
  mockIsHydrated.mockReturnValue(true);
  mockDescribe.mockReturnValue(outcome("unknown", "unknown"));
  // The login screen only ever completes for accounts the backend already knows:
  // a brand-new Google account is refused here with consent_required.
  mockStartGoogleAuth.mockResolvedValue({ navigated: false, redirectPath: "/dashboard", newUser: false });
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
    expect(mockTrackEvent).toHaveBeenCalledWith("auth_provider_clicked", {
      provider: "google",
      auth_screen: "login",
      intent: "login",
      source: "auth_screen",
      auth_attempt_id: expect.any(String),
    });
    const [, payload] = mockTrackEvent.mock.calls.find(([name]) => name === "auth_provider_clicked") ?? [];
    expect(payload).not.toHaveProperty("terms_accepted");
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
    expect(mockTrackEvent.mock.calls.filter(([name]) => name === "auth_provider_clicked")).toHaveLength(1);
  });
});

describe("Login screen — email flow", () => {
  it("tracks the email submit without terms_accepted", async () => {
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.type(screen.getByLabelText(messages.auth.email), "marcus@test.com");
    await user.type(screen.getByLabelText(messages.auth.password), "supersecret");
    await user.click(screen.getByRole("button", { name: messages.auth.signIn }));

    await waitFor(() => expect(mockSignIn).toHaveBeenCalledWith("marcus@test.com", "supersecret"));
    expect(mockTrackEvent).toHaveBeenCalledWith("auth_provider_clicked", {
      provider: "email",
      auth_screen: "login",
      intent: "login",
      source: "auth_screen",
      auth_attempt_id: expect.any(String),
    });
    const [, payload] = mockTrackEvent.mock.calls.find(([name]) => name === "auth_provider_clicked") ?? [];
    expect(payload).not.toHaveProperty("terms_accepted");
  });
});

describe("Login screen — unregistered Google account", () => {
  beforeEach(() => {
    mockIsNative.mockReturnValue(true);
    mockDescribe.mockReturnValue(outcome("consent_required", "backend_error", "consent_required", true));
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

  it("shows no error banner when the user dismissed the account picker", async () => {
    mockDescribe.mockReturnValue(outcome("cancelled", "user_cancelled", "USER_CANCELLED"));
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(googleButton()).not.toBeDisabled());
    expect(screen.queryByText(messages.auth.oauthError)).not.toBeInTheDocument();
    expect(screen.queryByText(messages.auth.googleAccountNotRegistered)).not.toBeInTheDocument();
  });

  it("reports a connectivity failure distinctly from a generic error", async () => {
    mockDescribe.mockReturnValue(outcome("network", "network_error", "exchange_failed", true));
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(screen.getByText(messages.auth.networkError)).toBeInTheDocument());
  });
});

// A dismissed picker is a decision. It has to be countable (so the funnel can
// tell it apart from a device that broke) without ever being filed as a defect.
describe("Login screen — the user cancelled the picker", () => {
  beforeEach(() => {
    mockIsNative.mockReturnValue(true);
    mockDescribe.mockReturnValue(outcome("cancelled", "user_cancelled", "USER_CANCELLED"));
    mockStartGoogleAuth.mockRejectedValue(new Error("Google Sign-In cancelled by user"));
  });

  it("emits exactly one social_login_failed, categorised as a cancellation", async () => {
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(eventsNamed("social_login_failed")).toHaveLength(1));
    const [, payload] = eventsNamed("social_login_failed")[0];
    expect(payload).toMatchObject({
      failure_category: "user_cancelled",
      error_code: "USER_CANCELLED",
      provider: "google",
      intent: "login",
      auth_screen: "login",
    });
    expect(eventsNamed("social_login_started")).toHaveLength(1);
  });

  it("does not report a client error nor an API error", async () => {
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(eventsNamed("social_login_failed")).toHaveLength(1));
    expect(eventsNamed("auth_client_error")).toHaveLength(0);
    expect(eventsNamed("auth_api_error")).toHaveLength(0);
  });

  it("shows a neutral notice the screen reader announces", async () => {
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    const notice = await screen.findByRole("status");
    expect(notice).toHaveTextContent(messages.auth.googleLoginCancelled);
  });

  it("clears the notice and mints a NEW attempt id on the retry", async () => {
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());
    await screen.findByRole("status");
    const first = attemptIdOf("social_login_started");

    mockStartGoogleAuth.mockResolvedValue({ navigated: true });
    await user.click(googleButton());

    await waitFor(() => expect(eventsNamed("social_login_started")).toHaveLength(2));
    const [, second] = eventsNamed("social_login_started")[1];
    expect((second as Record<string, string>).auth_attempt_id).not.toBe(first);
    expect(first).toBeTruthy();
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });
});

describe("Login screen — a real Google failure", () => {
  it("pairs social_login_failed with auth_client_error under the same attempt id", async () => {
    mockIsNative.mockReturnValue(true);
    mockDescribe.mockReturnValue(outcome("unknown", "provider_error", "plugin_login_failed"));
    mockStartGoogleAuth.mockRejectedValue(new Error("boom"));
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(eventsNamed("auth_client_error")).toHaveLength(1));
    const [, failed] = eventsNamed("social_login_failed")[0];
    const [, clientError] = eventsNamed("auth_client_error")[0];
    expect((failed as Record<string, string>).failure_category).toBe("provider_error");
    expect((clientError as Record<string, string>).failure_category).toBe("provider_error");
    expect((clientError as Record<string, string>).auth_attempt_id).toBe(
      (failed as Record<string, string>).auth_attempt_id,
    );
  });

  it("routes a backend failure to auth_api_error, not to the plugin bucket", async () => {
    mockIsNative.mockReturnValue(true);
    mockDescribe.mockReturnValue(outcome("unknown", "backend_error", "oauth_failed", true));
    mockStartGoogleAuth.mockRejectedValue(new Error("boom"));
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(eventsNamed("auth_api_error")).toHaveLength(1));
    expect(eventsNamed("social_login_failed")).toHaveLength(1);
    expect(eventsNamed("auth_client_error")).toHaveLength(0);
  });
});

describe("Login screen — the terminal success events", () => {
  it("closes the native Google attempt with a single social_login_completed", async () => {
    mockIsNative.mockReturnValue(true);
    const user = userEvent.setup();
    const { rerender } = render(<LoginPage />);

    await user.click(googleButton());

    await waitFor(() => expect(window.location.replace).toHaveBeenCalledWith("/dashboard"));
    const completions = mockTrackOnce.mock.calls.filter(([, name]) => name === "social_login_completed");
    expect(completions).toHaveLength(1);
    const [key, , payload] = completions[0];
    expect(key).toContain("social_login_completed:");
    expect(payload).toMatchObject({ provider: "google", intent: "login", auth_screen: "login" });

    // A rerender must not add a second conversion.
    rerender(<LoginPage />);
    expect(mockTrackOnce.mock.calls.filter(([, name]) => name === "social_login_completed")).toHaveLength(1);
  });

  it("emits login_completed once the email session exists", async () => {
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.type(screen.getByLabelText(messages.auth.email), "marcus@test.com");
    await user.type(screen.getByLabelText(messages.auth.password), "supersecret");
    await user.click(screen.getByRole("button", { name: messages.auth.signIn }));

    await waitFor(() =>
      expect(mockTrackOnce.mock.calls.filter(([, name]) => name === "login_completed")).toHaveLength(1),
    );
    const [, , payload] = mockTrackOnce.mock.calls.find(([, name]) => name === "login_completed")!;
    expect(payload).toMatchObject({ provider: "email", intent: "login", auth_screen: "login" });
    expect(JSON.stringify(payload)).not.toContain("marcus@test.com");
    expect(JSON.stringify(payload)).not.toContain("supersecret");
  });

  it("categorises a rejected credential without leaking it", async () => {
    const { ApiError } = await import("@/shared/lib/api");
    const rejected = new ApiError("Invalid email or password") as Error & { status: number };
    rejected.status = 401;
    mockSignIn.mockRejectedValueOnce(rejected);

    const user = userEvent.setup();
    render(<LoginPage />);

    await user.type(screen.getByLabelText(messages.auth.email), "marcus@test.com");
    await user.type(screen.getByLabelText(messages.auth.password), "wrongpass");
    await user.click(screen.getByRole("button", { name: messages.auth.signIn }));

    await waitFor(() => expect(eventsNamed("auth_api_error")).toHaveLength(1));
    const [, payload] = eventsNamed("auth_api_error")[0];
    expect(payload).toMatchObject({ stage: "email_login", failure_category: "invalid_credentials" });
    expect(JSON.stringify(payload)).not.toContain("marcus@test.com");
    expect(JSON.stringify(payload)).not.toContain("wrongpass");
  });
});

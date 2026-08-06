import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import SignUpPage from "@/app/sign-up/page";

// The sign-up screen's half of the auth telemetry: the terminal events that did
// not exist (social_login_completed), the ones that had to become exactly-once
// (signup_completed), and the cancellation that used to leave the screen
// identical and the funnel reading it as a defect.

const {
  mockIsNative,
  mockIsHydrated,
  mockStartGoogleAuth,
  mockDescribe,
  mockAuthLog,
  mockTrackEvent,
  mockTrackOnce,
  mockSignUp,
  mockPush,
} = vi.hoisted(() => ({
  mockIsNative: vi.fn(() => true),
  mockIsHydrated: vi.fn(() => true),
  mockStartGoogleAuth: vi.fn(),
  mockDescribe: vi.fn(),
  mockAuthLog: vi.fn(),
  mockTrackEvent: vi.fn(),
  mockTrackOnce: vi.fn(),
  mockSignUp: vi.fn(),
  mockPush: vi.fn(),
}));

function outcome(failure: string, category: string, errorCode = "boom", reachedBackend = false) {
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
  useSearchParams: () => new URLSearchParams(),
}));

vi.mock("@/features/auth/auth-context", () => ({ useAuth: () => ({ signUp: mockSignUp }) }));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: mockTrackEvent,
  trackOnce: mockTrackOnce,
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
  return screen.getByRole("button", { name: /Google|Carregando/i });
}

function consentCheckbox() {
  return screen.getByRole("checkbox", { name: /Termos de Uso/i });
}

async function openEmailForm(user: ReturnType<typeof userEvent.setup>) {
  await user.click(screen.getByRole("button", { name: /criar com e-mail/i }));
}

function eventsNamed(name: string) {
  return mockTrackEvent.mock.calls.filter(([eventName]) => eventName === name);
}

function onceNamed(name: string) {
  return mockTrackOnce.mock.calls.filter(([, eventName]) => eventName === name);
}

beforeEach(() => {
  vi.clearAllMocks();
  mockIsNative.mockReturnValue(true);
  mockIsHydrated.mockReturnValue(true);
  mockDescribe.mockReturnValue(outcome("unknown", "unknown"));
  mockStartGoogleAuth.mockResolvedValue({ navigated: false, redirectPath: "/onboarding" });
  Object.defineProperty(window, "location", {
    value: { replace: vi.fn(), assign: vi.fn(), href: "" },
    writable: true,
  });
});

describe("SignUp — the user cancelled the Google picker", () => {
  beforeEach(() => {
    mockDescribe.mockReturnValue(outcome("cancelled", "user_cancelled", "USER_CANCELLED"));
    mockStartGoogleAuth.mockRejectedValue(new Error("Google Sign-In cancelled by user"));
  });

  it("counts it once as a cancellation and never as a client error", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());
    await user.click(googleButton());

    await waitFor(() => expect(eventsNamed("social_login_failed")).toHaveLength(1));
    const [, payload] = eventsNamed("social_login_failed")[0];
    expect(payload).toMatchObject({
      failure_category: "user_cancelled",
      error_code: "USER_CANCELLED",
      intent: "sign_up",
      auth_screen: "sign_up",
    });
    expect(eventsNamed("auth_client_error")).toHaveLength(0);
    expect(eventsNamed("auth_api_error")).toHaveLength(0);
  });

  it("says so in a neutral notice and leaves the button usable", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());
    await user.click(googleButton());

    const notice = await screen.findByRole("status");
    expect(notice).toHaveTextContent(/Login cancelado/i);
    // Not the red error banner: cancelling is a decision, not a failure.
    expect(notice.className).not.toContain("red");
    expect(googleButton()).not.toBeDisabled();
  });

  it("clears the notice when a new attempt starts", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());
    await user.click(googleButton());
    await screen.findByRole("status");

    mockStartGoogleAuth.mockResolvedValue({ navigated: true });
    await user.click(googleButton());

    await waitFor(() => expect(screen.queryByRole("status")).not.toBeInTheDocument());
  });
});

describe("SignUp — terminal events", () => {
  it("closes a native Google sign-up with one social_login_completed", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());
    await user.click(googleButton());

    await waitFor(() => expect(window.location.replace).toHaveBeenCalledWith("/onboarding"));
    expect(onceNamed("social_login_completed")).toHaveLength(1);
    const [, , payload] = onceNamed("social_login_completed")[0];
    expect(payload).toMatchObject({ provider: "google", intent: "sign_up", auth_screen: "sign_up" });
  });

  it("emits signup_started and exactly one signup_completed for the email path", async () => {
    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());
    await openEmailForm(user);
    await user.type(screen.getByPlaceholderText("Seu nome"), "Marcus");
    await user.type(screen.getByPlaceholderText("seu@email.com"), "marcus@test.com");
    await user.type(screen.getByPlaceholderText("Mínimo 8 caracteres"), "supersecret");
    await user.click(screen.getByRole("button", { name: "Criar conta" }));

    await waitFor(() => expect(onceNamed("signup_completed")).toHaveLength(1));
    const [, started] = eventsNamed("signup_started")[0];
    const [key, , completed] = onceNamed("signup_completed")[0];
    expect((started as Record<string, string>).auth_attempt_id).toBe(
      (completed as Record<string, string>).auth_attempt_id,
    );
    expect(key).toContain("signup_completed:");
    expect(JSON.stringify(completed)).not.toContain("marcus@test.com");
    expect(JSON.stringify(completed)).not.toContain("supersecret");
  });

  it("categorises a rejected sign-up as a validation error", async () => {
    const { ApiError } = await import("@/shared/lib/api");
    const rejected = new ApiError("Email já cadastrado") as Error & { status: number };
    rejected.status = 422;
    mockSignUp.mockRejectedValueOnce(rejected);

    const user = userEvent.setup();
    render(<SignUpPage />);

    await user.click(consentCheckbox());
    await openEmailForm(user);
    await user.type(screen.getByPlaceholderText("Seu nome"), "Marcus");
    await user.type(screen.getByPlaceholderText("seu@email.com"), "marcus@test.com");
    await user.type(screen.getByPlaceholderText("Mínimo 8 caracteres"), "supersecret");
    await user.click(screen.getByRole("button", { name: "Criar conta" }));

    await waitFor(() => expect(eventsNamed("auth_api_error")).toHaveLength(1));
    const [, payload] = eventsNamed("auth_api_error")[0];
    expect(payload).toMatchObject({ stage: "email_signup", failure_category: "validation_error" });
    expect(onceNamed("signup_completed")).toHaveLength(0);
  });
});

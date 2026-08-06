import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import OnboardingPage from "@/app/onboarding/page";
import { saveDraft } from "@/features/plan-creation/draft";
import { buildInitialForm } from "@/features/plan-creation/types";
import { AnonApiError } from "@/features/anonymous/anon-api";
import { variantForInstallation, type PostOnboardingVariant } from "@/features/experiments/android-post-onboarding-gate";

// Diferente de post-onboarding-experiment-exposure.test.tsx, este NÃO faz mock de
// submit.ts: o que se mede aqui é justamente o despacho por modo dentro dele —
// que open_app fala com os endpoints anônimos, e que o 403 do 4º plano vira
// cadastro em vez da tela genérica de erro com um "Tentar novamente" inútil.
const {
  mockIsNative,
  mockIsHydrated,
  mockUseAuth,
  mockPush,
  mockReplace,
  mockTrackEvent,
  mockTrackOnce,
  mockInstallationId,
  mockGenerateAnonymous,
  mockSaveAnonymousProfile,
  mockLocationReplace,
} = vi.hoisted(() => ({
  mockIsNative: vi.fn(() => true),
  mockIsHydrated: vi.fn(() => true),
  mockUseAuth: vi.fn(() => ({ user: null, loading: false })),
  mockPush: vi.fn(),
  mockReplace: vi.fn(),
  mockTrackEvent: vi.fn(),
  mockTrackOnce: vi.fn(),
  mockInstallationId: vi.fn<() => string | undefined>(() => "install-1"),
  mockGenerateAnonymous: vi.fn(),
  mockSaveAnonymousProfile: vi.fn(),
  mockLocationReplace: vi.fn(),
}));

vi.mock("@/shared/lib/platform", () => ({
  useIsNativePlatform: () => mockIsNative(),
  useIsHydrated: () => mockIsHydrated(),
}));

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: mockPush, replace: mockReplace }) }));
vi.mock("@/features/auth/auth-context", () => ({ useAuth: () => mockUseAuth() }));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: mockTrackEvent,
  trackOnce: mockTrackOnce,
  EVENTS: {
    ONBOARDING_STARTED: "onboarding_started",
    ONBOARDING_COMPLETED: "onboarding_completed",
    SCREEN_VIEW: "screen_view",
    WORKOUT_CREATED: "workout_created",
    AI_WORKOUT_GENERATED: "ai_workout_generated",
  },
}));

vi.mock("@/shared/lib/analytics/context", () => ({
  isNativeApp: () => true,
  getCachedInstallationId: () => mockInstallationId(),
  getAnalyticsContext: () => ({ build_number: "60", platform: "android" }),
}));

vi.mock("@/shared/lib/analytics/installation", () => ({
  getInstallationId: () => Promise.resolve(mockInstallationId() ?? ""),
}));

vi.mock("@/shared/lib/onboarding-tracking", () => ({ trackOnboardingEvent: vi.fn() }));
vi.mock("@/shared/lib/api", () => ({
  api: { post: vi.fn(() => Promise.resolve({ status: "assigned" })), patch: vi.fn(() => Promise.resolve({})) },
  ApiError: class ApiError extends Error {
    status = 0;
  },
}));

vi.mock("@/features/anonymous/anonymous-plan", () => ({
  generateAnonymousPlan: mockGenerateAnonymous,
  saveAnonymousProfile: mockSaveAnonymousProfile,
}));

function installationIdFor(variant: PostOnboardingVariant): string {
  for (let i = 0; i < 1000; i++) {
    const id = `install-${i}`;
    if (variantForInstallation(id) === variant) return id;
  }
  throw new Error(`no installation id found for ${variant}`);
}

function draftAtPreview() {
  saveDraft({
    mode: "quick",
    stepId: "plan-preview",
    form: { ...buildInitialForm(), goal: "gain_muscle", training_location: "home" },
  });
}

describe("anonymous generation from the open_app variant", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    mockIsNative.mockReturnValue(true);
    mockIsHydrated.mockReturnValue(true);
    mockUseAuth.mockReturnValue({ user: null, loading: false });
    mockInstallationId.mockReturnValue(installationIdFor("open_app"));
    mockSaveAnonymousProfile.mockResolvedValue(undefined);
    vi.stubEnv("NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED", "true");
    vi.stubGlobal("location", { replace: mockLocationReplace, href: "http://localhost/onboarding" });
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("generates through the anonymous endpoints, never the authenticated one", async () => {
    mockGenerateAnonymous.mockResolvedValue({ id: 9, days: [{}, {}, {}] });
    draftAtPreview();
    const user = userEvent.setup();
    render(<OnboardingPage />);

    await user.click(await screen.findByRole("button", { name: /Ver meu treino/i }));

    await waitFor(() => expect(mockGenerateAnonymous).toHaveBeenCalledTimes(1));
    expect(mockSaveAnonymousProfile).toHaveBeenCalledTimes(1);
    await waitFor(() => expect(mockPush).toHaveBeenCalledWith("/plano/pronto"));
  });

  // O 4º plano não é erro recuperável: é a fronteira do que o produto entrega
  // sem conta. Cair na tela genérica ofereceria um "Tentar novamente" que o
  // servidor recusaria para sempre.
  it("sends the fourth attempt to sign-up instead of the retry screen", async () => {
    mockGenerateAnonymous.mockRejectedValue(
      new AnonApiError("anonymous_plan_limit_reached", 403, "anonymous_plan_limit_reached")
    );
    draftAtPreview();
    const user = userEvent.setup();
    render(<OnboardingPage />);

    await user.click(await screen.findByRole("button", { name: /Ver meu treino/i }));

    await waitFor(() =>
      expect(mockLocationReplace).toHaveBeenCalledWith("/sign-up?from=anonymous_limit")
    );
    expect(mockTrackEvent).toHaveBeenCalledWith(
      "anonymous_plan_limit_reached",
      expect.objectContaining({ onboarding_flow: "quick" })
    );
    expect(screen.queryByRole("button", { name: /Tentar novamente/i })).not.toBeInTheDocument();
  });

  // Uma falha real de geração continua sendo recuperável: ali o retry funciona.
  it("still shows the retry screen for an ordinary generation failure", async () => {
    mockGenerateAnonymous.mockRejectedValue(new AnonApiError("generation_failed", 500, "generation_failed"));
    draftAtPreview();
    const user = userEvent.setup();
    render(<OnboardingPage />);

    await user.click(await screen.findByRole("button", { name: /Ver meu treino/i }));

    await waitFor(() => expect(mockGenerateAnonymous).toHaveBeenCalled());
    expect(mockLocationReplace).not.toHaveBeenCalled();
  });

  it("keeps the account-gate variant on the authenticated path", async () => {
    mockInstallationId.mockReturnValue(installationIdFor("account_gate"));
    draftAtPreview();
    const user = userEvent.setup();
    render(<OnboardingPage />);

    await user.click(await screen.findByRole("button", { name: /Ver meu treino/i }));

    expect(mockPush).toHaveBeenCalledWith("/sign-up?from=onboarding");
    expect(mockGenerateAnonymous).not.toHaveBeenCalled();
  });
});

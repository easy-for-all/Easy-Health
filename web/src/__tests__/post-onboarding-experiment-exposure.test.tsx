import { StrictMode } from "react";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import OnboardingPage from "@/app/onboarding/page";
import { saveDraft } from "@/features/plan-creation/draft";
import { buildInitialForm } from "@/features/plan-creation/types";
import { variantForInstallation, type PostOnboardingVariant } from "@/features/experiments/android-post-onboarding-gate";

const {
  mockIsNative,
  mockIsHydrated,
  mockUseAuth,
  mockPush,
  mockReplace,
  mockTrackEvent,
  mockTrackOnce,
  mockTrackOnboardingEvent,
  mockUpsertProfile,
  mockGeneratePlan,
  mockInstallationId,
  mockPost,
} = vi.hoisted(() => ({
  mockIsNative: vi.fn(() => true),
  mockIsHydrated: vi.fn(() => true),
  mockUseAuth: vi.fn(() => ({ user: null, loading: false })),
  mockPush: vi.fn(),
  mockReplace: vi.fn(),
  mockTrackEvent: vi.fn(),
  mockTrackOnce: vi.fn(),
  mockTrackOnboardingEvent: vi.fn(),
  mockUpsertProfile: vi.fn(),
  mockGeneratePlan: vi.fn(),
  mockInstallationId: vi.fn<() => string | undefined>(() => "install-1"),
  mockPost: vi.fn(() => Promise.resolve({ status: "assigned", variant: "account_gate" })),
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
  getAnalyticsContext: () => ({ build_number: "60" }),
}));

vi.mock("@/shared/lib/analytics/installation", () => ({
  getInstallationId: () => Promise.resolve(mockInstallationId() ?? ""),
}));

vi.mock("@/shared/lib/onboarding-tracking", () => ({ trackOnboardingEvent: mockTrackOnboardingEvent }));
vi.mock("@/shared/lib/api", () => ({ api: { post: mockPost } }));
vi.mock("@/features/plan-creation/submit", () => ({
  upsertProfile: mockUpsertProfile,
  generatePlan: mockGeneratePlan,
}));

// Descobre um installation_id que caia na variante desejada em vez de fixar um
// valor de hash no teste. Assim o teste continua descrevendo o COMPORTAMENTO
// (esta variante faz isto) e não a aritmética interna do bucketer.
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

function useVariant(variant: PostOnboardingVariant) {
  mockInstallationId.mockReturnValue(installationIdFor(variant));
}

describe("post-onboarding experiment wiring", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    mockIsNative.mockReturnValue(true);
    mockIsHydrated.mockReturnValue(true);
    mockUseAuth.mockReturnValue({ user: null, loading: false });
    mockUpsertProfile.mockResolvedValue(undefined);
    mockGeneratePlan.mockResolvedValue({ id: 7, days: [{}, {}, {}] });
    vi.stubEnv("NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED", "true");
  });

  afterEach(() => vi.unstubAllEnvs());

  it("keeps the account gate exactly as it is today for account_gate", async () => {
    useVariant("account_gate");
    draftAtPreview();
    const user = userEvent.setup();
    render(<OnboardingPage />);

    await user.click(await screen.findByRole("button", { name: /Ver meu treino/i }));

    expect(mockPush).toHaveBeenCalledWith("/sign-up?from=onboarding");
    expect(mockGeneratePlan).not.toHaveBeenCalled();
    // O rascunho tem que atravessar o cadastro; é o que a variante A depende.
    expect(window.localStorage.getItem("eh_onboarding_draft")).not.toBeNull();
  });

  it("opens the app instead of the sign-up for open_app", async () => {
    useVariant("open_app");
    draftAtPreview();
    const user = userEvent.setup();
    render(<OnboardingPage />);

    await user.click(await screen.findByRole("button", { name: /Ver meu treino/i }));

    await waitFor(() => expect(mockGeneratePlan).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(mockPush).toHaveBeenCalledWith("/plano/pronto"));
    expect(mockPush).not.toHaveBeenCalledWith("/sign-up?from=onboarding");
  });

  // O resumo é o degrau comum das duas variantes. Se só uma o visse, a queda
  // medida entre elas incluiria uma tela a mais e não seria comparável.
  it("shows the plan summary in both variants", async () => {
    for (const variant of ["account_gate", "open_app"] as const) {
      window.localStorage.clear();
      useVariant(variant);
      draftAtPreview();
      const { unmount } = render(<OnboardingPage />);

      expect(await screen.findByText("Já temos o seu plano")).toBeInTheDocument();
      unmount();
    }
  });

  it("exposes only at the finish, never when the summary mounts", async () => {
    useVariant("open_app");
    draftAtPreview();
    const user = userEvent.setup();
    render(<OnboardingPage />);

    await screen.findByText("Já temos o seu plano");
    // Ver o resumo não é exposição: as duas variantes o veem, e quem para aqui
    // nunca chegou à bifurcação que o experimento mede.
    expect(mockTrackOnce).not.toHaveBeenCalledWith(
      expect.stringContaining("experiment_exposed"),
      "experiment_exposed",
      expect.anything()
    );

    await user.click(screen.getByRole("button", { name: /Ver meu treino/i }));

    expect(mockTrackOnce).toHaveBeenCalledWith(
      expect.stringContaining("experiment_exposed"),
      "experiment_exposed",
      expect.objectContaining({ variant: "open_app", exposure_point: "onboarding_completed" })
    );
    expect(mockTrackEvent).toHaveBeenCalledWith(
      "post_onboarding_destination_selected",
      expect.objectContaining({ variant: "open_app", destination: "app" })
    );
  });

  it("does not double-expose under StrictMode double rendering", async () => {
    useVariant("account_gate");
    draftAtPreview();
    const user = userEvent.setup();
    render(
      <StrictMode>
        <OnboardingPage />
      </StrictMode>
    );

    await user.click(await screen.findByRole("button", { name: /Ver meu treino/i }));

    const exposures = mockTrackOnce.mock.calls.filter(([, name]) => name === "experiment_exposed");
    expect(exposures).toHaveLength(1);
  });

  it("sends everyone to the account gate with the flag off, silently", async () => {
    vi.stubEnv("NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED", "false");
    useVariant("open_app"); // sorteado para o tratamento, mas o experimento está desligado
    draftAtPreview();
    const user = userEvent.setup();
    render(<OnboardingPage />);

    await user.click(await screen.findByRole("button", { name: /Ver meu treino/i }));

    expect(mockPush).toHaveBeenCalledWith("/sign-up?from=onboarding");
    expect(mockGeneratePlan).not.toHaveBeenCalled();
    expect(mockTrackOnce).not.toHaveBeenCalled();
    expect(mockPost).not.toHaveBeenCalled();
    expect(window.localStorage.getItem("eh_experiments")).toBeNull();
  });

  it("leaves the web out of the experiment entirely", async () => {
    mockIsNative.mockReturnValue(false);
    render(<OnboardingPage />);

    await waitFor(() => expect(mockReplace).toHaveBeenCalledWith("/login"));
    expect(mockPost).not.toHaveBeenCalled();
    expect(window.localStorage.getItem("eh_experiments")).toBeNull();
  });

  it("does not enrol an authenticated user resuming a draft", async () => {
    useVariant("open_app");
    draftAtPreview();
    mockUseAuth.mockReturnValue({ user: { id: 1 }, loading: false });

    render(<OnboardingPage />);

    await waitFor(() => expect(mockGeneratePlan).toHaveBeenCalledTimes(1));
    // Retomada pós-cadastro segue para o destino autenticado de sempre.
    await waitFor(() => expect(mockPush).toHaveBeenCalledWith("/workouts/ready"));
    expect(window.localStorage.getItem("eh_experiments")).toBeNull();
  });
});

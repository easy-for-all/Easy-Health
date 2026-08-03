import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import OnboardingPage from "@/app/onboarding/page";
import { saveDraft } from "@/features/plan-creation/draft";
import { buildInitialForm } from "@/features/plan-creation/types";

const {
  mockIsNative,
  mockIsHydrated,
  mockUseAuth,
  mockReplace,
  mockPush,
  mockTrackEvent,
  mockTrackOnboardingEvent,
  mockUpsertProfile,
  mockGeneratePlan,
} = vi.hoisted(() => ({
  mockIsNative: vi.fn(() => true),
  mockIsHydrated: vi.fn(() => true),
  mockUseAuth: vi.fn(() => ({ user: null, loading: false })),
  mockReplace: vi.fn(),
  mockPush: vi.fn(),
  mockTrackEvent: vi.fn(),
  mockTrackOnboardingEvent: vi.fn(),
  mockUpsertProfile: vi.fn(),
  mockGeneratePlan: vi.fn(),
}));

vi.mock("@/shared/lib/platform", () => ({
  useIsNativePlatform: () => mockIsNative(),
  useIsHydrated: () => mockIsHydrated(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush, replace: mockReplace }),
}));

vi.mock("@/features/auth/auth-context", () => ({
  useAuth: () => mockUseAuth(),
}));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: mockTrackEvent,
  EVENTS: {
    ONBOARDING_STARTED: "onboarding_started",
    ONBOARDING_COMPLETED: "onboarding_completed",
    SCREEN_VIEW: "screen_view",
    WORKOUT_CREATED: "workout_created",
    AI_WORKOUT_GENERATED: "ai_workout_generated",
  },
}));

vi.mock("@/shared/lib/onboarding-tracking", () => ({
  trackOnboardingEvent: mockTrackOnboardingEvent,
}));

vi.mock("@/features/plan-creation/submit", () => ({
  upsertProfile: mockUpsertProfile,
  generatePlan: mockGeneratePlan,
}));

function draftAtPreview() {
  saveDraft({
    mode: "quick",
    stepId: "plan-preview",
    form: { ...buildInitialForm(), goal: "gain_muscle", training_location: "home" },
  });
}

describe("onboarding entry decision", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    mockIsNative.mockReturnValue(true);
    mockIsHydrated.mockReturnValue(true);
    mockUseAuth.mockReturnValue({ user: null, loading: false });
    mockUpsertProfile.mockResolvedValue(undefined);
    mockGeneratePlan.mockResolvedValue({ id: 7, days: [{}, {}, {}] });
  });

  it("renders nothing until hydration, so the draft is read only on the client", () => {
    mockIsHydrated.mockReturnValue(false);
    const { container } = render(<OnboardingPage />);

    expect(container).toBeEmptyDOMElement();
  });

  it("lets an unauthenticated native visitor start the wizard", async () => {
    render(<OnboardingPage />);

    expect(mockReplace).not.toHaveBeenCalled();
    expect(await screen.findByText(/Como você quer começar/i)).toBeInTheDocument();
  });

  // A Web mantém landing → cadastro → onboarding. Sem este guard, abrir a lista
  // de caminhos públicos do AuthProvider teria aberto o onboarding para a Web junto.
  it("sends an unauthenticated web visitor to /login", () => {
    mockIsNative.mockReturnValue(false);
    render(<OnboardingPage />);

    expect(mockReplace).toHaveBeenCalledWith("/login");
    expect(mockTrackEvent).not.toHaveBeenCalledWith("onboarding_started");
  });

  it("waits for the session check before deciding anything", () => {
    mockUseAuth.mockReturnValue({ user: null, loading: true });
    mockIsNative.mockReturnValue(false);
    const { container } = render(<OnboardingPage />);

    // Sem esta espera, um usuário logado seria expulso para /login no intervalo
    // entre a montagem e a resposta de /auth/me.
    expect(mockReplace).not.toHaveBeenCalled();
    expect(container).toBeEmptyDOMElement();
  });

  it("resumes the draft and generates without a second tap after sign-up", async () => {
    draftAtPreview();
    mockUseAuth.mockReturnValue({ user: { id: 1 }, loading: false });

    render(<OnboardingPage />);

    await waitFor(() => expect(mockGeneratePlan).toHaveBeenCalledTimes(1));
    expect(mockUpsertProfile).toHaveBeenCalledTimes(1);
    expect(mockTrackEvent).toHaveBeenCalledWith(
      "onboarding_draft_resumed",
      expect.objectContaining({ onboarding_flow: "quick", step_id: "plan-preview" }),
    );
    // users.onboarding_flow é escrito por um endpoint autenticado que não existia
    // quando a escolha do fluxo foi feita; sem reemitir, a atribuição se perde.
    expect(mockTrackOnboardingEvent).toHaveBeenCalledWith(
      "onboarding_flow_selected",
      expect.objectContaining({ onboardingFlow: "quick" }),
    );
    await waitFor(() => expect(mockPush).toHaveBeenCalledWith("/workouts/ready"));
  });

  it("does not auto-generate for an authenticated user without a draft", async () => {
    mockUseAuth.mockReturnValue({ user: { id: 1 }, loading: false });

    render(<OnboardingPage />);

    expect(await screen.findByText(/Como você quer começar/i)).toBeInTheDocument();
    expect(mockGeneratePlan).not.toHaveBeenCalled();
  });
});

describe("pre-auth preview hands over to sign-up", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    mockIsNative.mockReturnValue(true);
    mockIsHydrated.mockReturnValue(true);
    mockUseAuth.mockReturnValue({ user: null, loading: false });
  });

  it("summarises the answers and asks for the account, without calling the API", async () => {
    draftAtPreview();
    const user = userEvent.setup();
    render(<OnboardingPage />);

    expect(await screen.findByText("Já temos o seu plano")).toBeInTheDocument();
    expect(screen.getByText("Hipertrofia")).toBeInTheDocument();
    expect(screen.getByText("Casa")).toBeInTheDocument();
    expect(mockTrackEvent).toHaveBeenCalledWith("plan_preview_viewed", expect.any(Object));
    // A geração é síncrona, leva até 90s e pode falhar. Prometer um treino pronto
    // aqui seria uma promessa que a tela seguinte não consegue cumprir.
    expect(mockGeneratePlan).not.toHaveBeenCalled();

    await user.click(screen.getByRole("button", { name: /Ver meu treino/i }));

    expect(mockPush).toHaveBeenCalledWith("/sign-up?from=onboarding");
    expect(mockGeneratePlan).not.toHaveBeenCalled();
  });

  it("keeps the draft when handing over, so the answers survive the sign-up", async () => {
    draftAtPreview();
    const user = userEvent.setup();
    render(<OnboardingPage />);

    await user.click(await screen.findByRole("button", { name: /Ver meu treino/i }));

    expect(window.localStorage.getItem("eh_onboarding_draft")).not.toBeNull();
  });
});

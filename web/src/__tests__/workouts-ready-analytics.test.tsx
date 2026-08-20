import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import WorkoutReadyPage from "@/app/(app)/workouts/ready/page";

// /workouts/ready é o destino padrão depois que o plano é criado no onboarding
// autenticado. Ela MOSTRA o treino — nome, contagem, grupos musculares, lista de
// exercícios — mas só emitia activation_ready_screen_viewed, que vai para o
// pipeline de onboarding_events, não para product_analytics_events.
// Resultado: quem via o treino aqui e não dava mais um toque até /workout/today
// era contado no funil como "nunca viu o treino".

const {
  trackEventMock,
  trackOnceMock,
  trackOnboardingEventMock,
  apiGet,
  routerPush,
} = vi.hoisted(() => ({
  trackEventMock: vi.fn(),
  trackOnceMock: vi.fn(),
  trackOnboardingEventMock: vi.fn(),
  apiGet: vi.fn(),
  routerPush: vi.fn(),
}));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: trackEventMock,
  trackOnce: trackOnceMock,
  EVENTS: { PAYWALL_VIEWED: "paywall_viewed", SCREEN_VIEW: "screen_view" },
}));

vi.mock("@/shared/lib/onboarding-tracking", () => ({
  trackOnboardingEvent: trackOnboardingEventMock,
}));

vi.mock("@/shared/lib/api", () => ({ api: { get: apiGet } }));

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: routerPush }) }));

// O gate tem teste próprio (upgrade-gate-loading). Aqui ele só não pode impedir
// a tela de montar.
vi.mock("@/shared/components/upgrade-gate", () => ({
  UpgradeGate: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

// canvas-confetti agenda animation frames que sobrevivem ao unmount, e jsdom não
// tem canvas: sem isto o frame estoura depois do teste como erro não tratado.
vi.mock("@/shared/components/motion", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/shared/components/motion")>()),
  ConfettiBurst: () => null,
}));

vi.mock("@/features/auth/auth-context", () => ({ useAuth: () => ({ user: null }) }));
vi.mock("@/features/notifications/pre-permission-card", () => ({ PrePermissionCard: () => null }));
vi.mock("@/features/notifications/push-feedback-link", () => ({ PushFeedbackLink: () => null }));
vi.mock("@/features/app-promo/app-promo-card", () => ({ AppPromoCard: () => null }));
vi.mock("@/features/workout/progressive-profiling-sheet", () => ({ ProgressiveProfilingSheet: () => null }));
vi.mock("@/shared/components/workout/exercise-info-modal", () => ({ ExerciseInfoModal: () => null }));

const PLAN = { id: 77, days: [{ id: 11 }] };
const DAY = {
  id: 11,
  name: "Treino A",
  exercises: [
    { workout_day_exercise_id: 101, exercise_id: 501, name: "Supino", sets: 3, reps: 10, muscle_group: "chest" },
  ],
};

function mockApi({ plan, today }: { plan: unknown; today: unknown }) {
  apiGet.mockImplementation((path: string) => {
    if (path === "/api/v1/workout_plan") return Promise.resolve(plan);
    if (path === "/api/v1/workout_plan/today") return Promise.resolve(today);
    return Promise.resolve({ day: DAY });
  });
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("/workouts/ready — workout_viewed", () => {
  it("emite quando o treino foi resolvido", async () => {
    mockApi({ plan: PLAN, today: { day: DAY } });

    render(<WorkoutReadyPage />);

    await waitFor(() => expect(trackOnceMock).toHaveBeenCalled());
    expect(trackOnceMock).toHaveBeenCalledWith(
      "workout_viewed:ready",
      "workout_viewed",
      expect.objectContaining({
        source: "workouts_ready",
        workout_plan_id: 77,
        workout_day_id: 11,
      }),
    );
  });

  it("NÃO emite quando não há treino para mostrar", async () => {
    // Sem dia resolvido não houve visualização de treino. Emitir aqui inflaria o
    // degrau com uma tela que não mostrou treino nenhum.
    mockApi({ plan: null, today: { day: null } });

    render(<WorkoutReadyPage />);

    await waitFor(() => expect(trackOnboardingEventMock).toHaveBeenCalled());
    expect(trackOnceMock).not.toHaveBeenCalled();
  });

  it("preserva activation_ready_screen_viewed — é outro pipeline", async () => {
    mockApi({ plan: PLAN, today: { day: DAY } });

    render(<WorkoutReadyPage />);

    await waitFor(() =>
      expect(trackOnboardingEventMock).toHaveBeenCalledWith(
        "activation_ready_screen_viewed",
        expect.anything(),
      ),
    );
  });
});

describe("/workouts/ready — workout_start_clicked", () => {
  it("emite no CTA e continua navegando para o treino", async () => {
    mockApi({ plan: PLAN, today: { day: DAY } });
    const user = userEvent.setup();

    render(<WorkoutReadyPage />);
    await waitFor(() => expect(trackOnceMock).toHaveBeenCalled());

    await user.click(screen.getByRole("button", { name: /Iniciar treino/i }));

    expect(routerPush).toHaveBeenCalledWith("/workout/today?day=11");
    expect(trackEventMock).toHaveBeenCalledWith("workout_start_clicked", {
      source: "workouts_ready",
      workout_day_id: 11,
    });
  });

  it("preserva activation_start_clicked — os dois pipelines convivem", async () => {
    mockApi({ plan: PLAN, today: { day: DAY } });
    const user = userEvent.setup();

    render(<WorkoutReadyPage />);
    await waitFor(() => expect(trackOnceMock).toHaveBeenCalled());

    await user.click(screen.getByRole("button", { name: /Iniciar treino/i }));

    expect(trackOnboardingEventMock).toHaveBeenCalledWith(
      "activation_start_clicked",
      expect.anything(),
    );
  });

  it("não emite workout_start_clicked no CTA de ver o treino completo", async () => {
    mockApi({ plan: PLAN, today: { day: DAY } });
    const user = userEvent.setup();

    render(<WorkoutReadyPage />);
    await waitFor(() => expect(trackOnceMock).toHaveBeenCalled());

    await user.click(screen.getByRole("button", { name: /Ver treino completo/i }));

    expect(routerPush).toHaveBeenCalledWith("/workouts");
    expect(trackEventMock).not.toHaveBeenCalledWith("workout_start_clicked", expect.anything());
  });
});

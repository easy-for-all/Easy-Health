import { render, screen } from "@testing-library/react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { UpgradeGate } from "@/shared/components/upgrade-gate";

// useSubscription lia user?.billing_status sem olhar o loading do useAuth.
// AuthProvider começa com user null e só resolve depois de GET /auth/me, então o
// primeiro render de qualquer tela sob o gate concluía "não tem acesso" e
// mostrava o paywall — inclusive para quem paga. Além do flash, isso emitia um
// paywall_viewed que nunca correspondeu a um paywall que alguém decidiu ver.

const { useAuthMock, trackEventMock } = vi.hoisted(() => ({
  useAuthMock: vi.fn(),
  trackEventMock: vi.fn(),
}));

vi.mock("@/features/auth/auth-context", () => ({ useAuth: useAuthMock }));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: trackEventMock,
  EVENTS: { PAYWALL_VIEWED: "paywall_viewed", SCREEN_VIEW: "screen_view" },
}));

beforeEach(() => {
  vi.clearAllMocks();
});

const PAID = {
  paid: true,
  status: "active",
  plan: "pro",
  app_trial_active: false,
  access_locked: false,
};

const NO_ACCESS = {
  paid: false,
  status: "canceled",
  plan: "none",
  app_trial_active: false,
  access_locked: false,
};

function Protected() {
  return <p>conteúdo do treino</p>;
}

describe("UpgradeGate — sessão ainda carregando", () => {
  beforeEach(() => {
    useAuthMock.mockReturnValue({ user: null, loading: true });
  });

  it("não mostra o paywall antes de saber quem é o usuário", () => {
    render(<UpgradeGate><Protected /></UpgradeGate>);

    expect(screen.queryByText(/Eleve seus treinos/i)).not.toBeInTheDocument();
  });

  it("não emite paywall_viewed", () => {
    render(<UpgradeGate><Protected /></UpgradeGate>);

    expect(trackEventMock).not.toHaveBeenCalledWith("paywall_viewed");
    expect(trackEventMock).not.toHaveBeenCalled();
  });
});

describe("UpgradeGate — sessão resolvida", () => {
  it("mostra o paywall para quem realmente não tem acesso", () => {
    useAuthMock.mockReturnValue({ user: { billing_status: NO_ACCESS }, loading: false });

    render(<UpgradeGate><Protected /></UpgradeGate>);

    expect(screen.getByText(/Eleve seus treinos/i)).toBeInTheDocument();
    expect(screen.queryByText("conteúdo do treino")).not.toBeInTheDocument();
    expect(trackEventMock).toHaveBeenCalledWith("paywall_viewed");
  });

  it("libera o conteúdo para quem tem acesso", () => {
    useAuthMock.mockReturnValue({ user: { billing_status: PAID }, loading: false });

    render(<UpgradeGate><Protected /></UpgradeGate>);

    expect(screen.getByText("conteúdo do treino")).toBeInTheDocument();
    expect(trackEventMock).not.toHaveBeenCalled();
  });

  it("libera o conteúdo durante o trial de app", () => {
    useAuthMock.mockReturnValue({
      user: { billing_status: { ...NO_ACCESS, app_trial_active: true } },
      loading: false,
    });

    render(<UpgradeGate><Protected /></UpgradeGate>);

    expect(screen.getByText("conteúdo do treino")).toBeInTheDocument();
  });
});

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { NativeEntryGate } from "@/features/native-entry/native-entry-gate";
import { NativeEntryScreen } from "@/features/native-entry/native-entry-screen";

const {
  mockHydrated,
  mockIsNative,
  mockAuth,
  mockReplace,
  mockTrackOnce,
  mockTrackLoginSelected,
  mockTrackSignupSelected,
} = vi.hoisted(() => ({
  mockHydrated: vi.fn(() => true),
  mockIsNative: vi.fn(() => true),
  mockAuth: vi.fn(() => ({ user: null, loading: false })),
  mockReplace: vi.fn(),
  mockTrackOnce: vi.fn(),
  mockTrackLoginSelected: vi.fn(),
  mockTrackSignupSelected: vi.fn(),
}));

vi.mock("@/shared/lib/platform", () => ({
  useIsHydrated: () => mockHydrated(),
  useIsNativePlatform: () => mockIsNative(),
}));

vi.mock("@/features/auth/auth-context", () => ({
  useAuth: () => mockAuth(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: mockReplace }),
}));

vi.mock("@/shared/lib/analytics", () => ({
  trackOnce: mockTrackOnce,
}));

vi.mock("@/features/auth/auth-analytics", () => ({
  trackLoginSelected: mockTrackLoginSelected,
  trackSignupSelected: mockTrackSignupSelected,
}));

describe("NativeEntryGate", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockHydrated.mockReturnValue(true);
    mockIsNative.mockReturnValue(true);
    mockAuth.mockReturnValue({ user: null, loading: false });
  });

  it("renders only a neutral loading state while runtime or auth is unresolved", () => {
    mockHydrated.mockReturnValue(false);
    mockAuth.mockReturnValue({ user: null, loading: true });

    render(<NativeEntryGate />);

    expect(screen.getByLabelText("Carregando")).toBeInTheDocument();
    expect(screen.queryByText("Seu treino personalizado em menos de 1 minuto.")).not.toBeInTheDocument();
  });

  it("renders the native entry screen for unauthenticated native Android", () => {
    render(<NativeEntryGate />);

    expect(screen.getByRole("heading", { name: "Seu treino personalizado em menos de 1 minuto." })).toBeInTheDocument();
    expect(mockReplace).not.toHaveBeenCalled();
  });

  it("redirects browsers back to the public landing", async () => {
    mockIsNative.mockReturnValue(false);

    render(<NativeEntryGate />);

    expect(screen.getByLabelText("Carregando")).toBeInTheDocument();
    expect(screen.queryByText("Seu treino personalizado em menos de 1 minuto.")).not.toBeInTheDocument();
    await waitFor(() => expect(mockReplace).toHaveBeenCalledWith("/"));
  });

  it("redirects authenticated native users to the dashboard", async () => {
    mockAuth.mockReturnValue({ user: { id: 123 }, loading: false });

    render(<NativeEntryGate />);

    expect(screen.getByLabelText("Carregando")).toBeInTheDocument();
    expect(screen.queryByText("Seu treino personalizado em menos de 1 minuto.")).not.toBeInTheDocument();
    await waitFor(() => expect(mockReplace).toHaveBeenCalledWith("/dashboard"));
  });
});

describe("NativeEntryScreen", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("emits native_entry_viewed once and not on rerender", () => {
    const { rerender } = render(<NativeEntryScreen />);

    expect(mockTrackOnce).toHaveBeenCalledTimes(1);
    expect(mockTrackOnce).toHaveBeenCalledWith("native_entry_viewed", "native_entry_viewed", {
      source: "native_app",
      platform: "android",
    });

    rerender(<NativeEntryScreen />);
    expect(mockTrackOnce).toHaveBeenCalledTimes(1);
  });

  it("routes the CTAs and emits the native origin", async () => {
    const user = userEvent.setup();
    render(<NativeEntryScreen />);

    const signup = screen.getByRole("link", { name: "Criar meu treino grátis" });
    const login = screen.getByRole("link", { name: "Já tenho uma conta" });

    // A ação principal entra no onboarding, não no cadastro: no app não existe a
    // landing longa da Web, então a conta é pedida depois do resumo do plano.
    expect(signup).toHaveAttribute("href", "/onboarding?intent=sign_up&from=native_entry");
    // "Já tenho uma conta" continua indo direto para o login — quem já é usuário
    // não pode ser obrigado a atravessar o onboarding para entrar.
    expect(login).toHaveAttribute("href", "/login?intent=login&from=native_entry");

    await user.click(signup);
    await user.click(login);

    expect(mockTrackSignupSelected).toHaveBeenCalledWith("native_entry");
    expect(mockTrackLoginSelected).toHaveBeenCalledWith("native_entry");
  });
});

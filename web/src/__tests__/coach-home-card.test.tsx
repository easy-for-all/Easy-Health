import { render, screen, waitFor, act } from "@testing-library/react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { CoachHomeCard } from "@/shared/components/coach-home-card";

const { mockGet } = vi.hoisted(() => ({ mockGet: vi.fn() }));

vi.mock("@/shared/lib/api", () => ({
  api: { get: mockGet },
}));

vi.mock("@/shared/components/coach-recommendation-card", () => ({
  CoachRecommendationCard: ({ onResolved }: { onResolved?: () => void }) => (
    <div data-testid="coach-recommendation-card">
      <button onClick={onResolved}>resolve</button>
    </div>
  ),
}));

vi.mock("@/shared/components/coach-insights-section", () => ({
  CoachInsightsSection: () => <div data-testid="coach-insights-section" />,
}));

const pendingRec = {
  id: 1,
  type: "weight_progression",
  status: "pending" as const,
  title: "Aumentar carga",
  message: "Você está pronto para progredir.",
  exercise: { id: 10, name: "Supino Reto" },
  current_value: 60,
  recommended_value: 65,
  unit: "kg",
  confidence: 0.9,
  reasons: ["3 semanas com a mesma carga"],
  actions: [],
};

describe("CoachHomeCard", () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it("recommendation pending → exibe apenas CoachRecommendationCard", async () => {
    mockGet.mockResolvedValue({ recommendation: pendingRec });

    render(<CoachHomeCard />);

    await waitFor(() => {
      expect(screen.getByTestId("coach-recommendation-card")).toBeInTheDocument();
      expect(screen.queryByTestId("coach-insights-section")).not.toBeInTheDocument();
    });
  });

  it("recommendation accepted → CoachRecommendationCard desaparece, CoachInsightsSection aparece", async () => {
    mockGet
      .mockResolvedValueOnce({ recommendation: pendingRec })
      .mockResolvedValueOnce({ recommendation: null });

    render(<CoachHomeCard />);

    await waitFor(() => {
      expect(screen.getByTestId("coach-recommendation-card")).toBeInTheDocument();
    });

    await act(async () => {
      screen.getByRole("button", { name: "resolve" }).click();
    });

    await waitFor(() => {
      expect(screen.queryByTestId("coach-recommendation-card")).not.toBeInTheDocument();
      expect(screen.getByTestId("coach-insights-section")).toBeInTheDocument();
    });
  });

  it("recommendation dismissed → CoachRecommendationCard desaparece, CoachInsightsSection aparece", async () => {
    mockGet
      .mockResolvedValueOnce({ recommendation: pendingRec })
      .mockResolvedValueOnce({ recommendation: null });

    render(<CoachHomeCard />);

    await waitFor(() => {
      expect(screen.getByTestId("coach-recommendation-card")).toBeInTheDocument();
    });

    await act(async () => {
      screen.getByRole("button", { name: "resolve" }).click();
    });

    await waitFor(() => {
      expect(screen.queryByTestId("coach-recommendation-card")).not.toBeInTheDocument();
      expect(screen.getByTestId("coach-insights-section")).toBeInTheDocument();
    });
  });

  it("sem recommendation → exibe apenas CoachInsightsSection", async () => {
    mockGet.mockResolvedValue({ recommendation: null });

    render(<CoachHomeCard />);

    await waitFor(() => {
      expect(screen.getByTestId("coach-insights-section")).toBeInTheDocument();
      expect(screen.queryByTestId("coach-recommendation-card")).not.toBeInTheDocument();
    });
  });

  it("nunca renderiza dois cards simultaneamente", async () => {
    mockGet.mockResolvedValue({ recommendation: pendingRec });

    render(<CoachHomeCard />);

    // Durante loading: nenhum card
    expect(screen.queryByTestId("coach-recommendation-card")).not.toBeInTheDocument();
    expect(screen.queryByTestId("coach-insights-section")).not.toBeInTheDocument();

    // Após loading: exatamente um card
    await waitFor(() => {
      const recCard = screen.queryByTestId("coach-recommendation-card");
      const insights = screen.queryByTestId("coach-insights-section");
      expect(Boolean(recCard) && Boolean(insights)).toBe(false);
      expect(Boolean(recCard) || Boolean(insights)).toBe(true);
    });
  });
});

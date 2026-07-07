import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { OnboardingAnalyticsSection } from "@/app/(app)/admin/onboarding-analytics";
import type { OnboardingAnalytics } from "@/app/(app)/admin/onboarding-analytics/types";

const { mockGet } = vi.hoisted(() => ({ mockGet: vi.fn() }));

vi.mock("@/shared/lib/api", () => ({
  api: { get: mockGet },
}));

const emptyAnalytics: OnboardingAnalytics = {
  flow_selection: { total: 0, by_flow: {} },
  conversion_by_flow: {
    quick: {
      label: "Rápido", selected: 0, created_workout: 0, executed_first: 0,
      plus2_sessions: 0, plus3_sessions: 0, subscribed: 0,
      conversion_to_workout_pct: 0, conversion_to_subscription_pct: 0,
    },
  },
  time_to_first_plan: { quick: { label: "Rápido", count: 0 } },
  step_dropoff: { quick: [] },
  first_workout_24h: {
    overall: {
      signup_to_first_workout_24h: 0, signup_to_first_workout_24h_pct: 0,
      plan_to_first_workout_24h: 0, plan_to_first_workout_24h_pct: 0,
      avg_time_label: null, median_time_label: null,
    },
    by_flow: {},
  },
  progressive_profiling: {
    summary: { shown: 0, answered: 0, skipped: 0, answer_rate_pct: 0, skip_rate_pct: 0 },
    by_question: [],
  },
  ai_quality: {
    photo_ai: {
      label: "Foto IA", summaries_generated: 0, summaries_edited: 0, plans_accepted: 0,
      plans_regenerated: 0, plans_abandoned: 0, acceptance_pct: 0, edit_pct: 0,
      regeneration_pct: 0, abandonment_pct: 0,
    },
  },
  declared_preferences: {
    goals: [], locations: [], durations: [], frequencies: [], limitations: [],
    training_preference: { intensity: [], style: [] },
  },
};

const populatedAnalytics: OnboardingAnalytics = {
  ...emptyAnalytics,
  flow_selection: {
    total: 10,
    by_flow: { quick: { label: "Rápido", count: 7, pct: 70 }, complete: { label: "Completo", count: 3, pct: 30 } },
  },
};

describe("OnboardingAnalyticsSection", () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it("shows empty states when there is no data yet", async () => {
    mockGet.mockResolvedValue({ onboarding_analytics: emptyAnalytics });

    render(<OnboardingAnalyticsSection />);

    await waitFor(() => {
      expect(screen.getAllByText("Sem dados ainda").length).toBeGreaterThan(0);
    });
  });

  it("renders flow selection counts when data is present", async () => {
    mockGet.mockResolvedValue({ onboarding_analytics: populatedAnalytics });

    render(<OnboardingAnalyticsSection />);

    await waitFor(() => {
      expect(screen.getAllByText("Rápido").length).toBeGreaterThan(1);
      expect(screen.getByText("7")).toBeInTheDocument();
    });
  });

  it("refetches with the selected flow filter as a query param", async () => {
    mockGet.mockResolvedValue({ onboarding_analytics: populatedAnalytics });
    const user = userEvent.setup();

    render(<OnboardingAnalyticsSection />);

    await waitFor(() => expect(mockGet).toHaveBeenCalled());

    await user.click(screen.getByRole("button", { name: "Completo" }));

    await waitFor(() => {
      const lastCall = mockGet.mock.calls.at(-1)?.[0] as string;
      expect(lastCall).toContain("onboarding_flow=complete");
    });
  });
});

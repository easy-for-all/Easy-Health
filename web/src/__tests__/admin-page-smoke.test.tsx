import { render, screen, waitFor } from "@testing-library/react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import AdminPage from "@/app/(app)/admin/page";

const { mockGet, mockPush, mockReplace } = vi.hoisted(() => ({
  mockGet: vi.fn(),
  mockPush: vi.fn(),
  mockReplace: vi.fn(),
}));

vi.mock("@/shared/lib/api", () => ({
  api: { get: mockGet },
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush, replace: mockReplace }),
}));

vi.mock("@/features/auth/auth-context", () => ({
  useAuth: () => ({ user: { id: 1, admin: true }, loading: false }),
}));

const baseStats = {
  total_users: 5,
  trial_active_count: 2,
  trial_expired_count: 1,
  premium_count: 1,
  stripe_trialing_count: 0,
  users_created_workouts: 3,
  users_completed_workouts: 2,
  users_with_2plus_sessions: 1,
  users_with_3plus_sessions: 0,
  active_last_7_days: 1,
  active_last_30_days: 2,
  retention_d1: 10,
  retention_d7: 5,
  retention_d30: 2,
  conversion_trial_to_subscription: 20,
  conversion_signup_to_workout_created: 60,
  conversion_plan_to_session: 66.7,
  conversion_session_to_subscription: 50,
  total_workout_plans: 3,
  total_workout_sessions: 4,
  total_uploads: 0,
};

const emptyOnboardingAnalytics = {
  flow_selection: { total: 0, by_flow: {} },
  conversion_by_flow: {},
  time_to_first_plan: {},
  step_dropoff: {},
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
  ai_quality: {},
  declared_preferences: {
    goals: [], locations: [], durations: [], frequencies: [], limitations: [],
    training_preference: { intensity: [], style: [] },
  },
};

describe("AdminPage", () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it("renders legacy sections and the new Onboarding Analytics section without crashing", async () => {
    mockGet.mockImplementation((path: string) => {
      if (path.startsWith("/api/v1/admin/stats")) {
        return Promise.resolve({ ...baseStats, onboarding_analytics: emptyOnboardingAnalytics });
      }
      if (path.startsWith("/api/v1/admin/users")) {
        return Promise.resolve({ users: [], total: 0, page: 1, per: 25 });
      }
      return Promise.reject(new Error(`unexpected path ${path}`));
    });

    render(<AdminPage />);

    await waitFor(() => {
      expect(screen.getByText("Painel Administrativo")).toBeInTheDocument();
      expect(screen.getByText("Status de acesso")).toBeInTheDocument();
      expect(screen.getByText("Onboarding Analytics")).toBeInTheDocument();
      expect(screen.getByText("Usuários", { selector: "h2" })).toBeInTheDocument();
    });
  });
});

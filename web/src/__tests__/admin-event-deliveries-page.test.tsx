import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import EventDeliveriesPage from "@/app/(app)/admin/analytics/event-deliveries/page";

const { mockGet, mockReplace } = vi.hoisted(() => ({
  mockGet: vi.fn(),
  mockReplace: vi.fn(),
}));

vi.mock("@/shared/lib/api", () => ({
  api: { get: mockGet },
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: mockReplace }),
}));

vi.mock("@/features/auth/auth-context", () => ({
  useAuth: () => ({ user: { id: 1, admin: true }, loading: false }),
}));

const listResponse = {
  summary: {
    events_generated: 1,
    accepted_by_make: 1,
    with_error: 0,
    pending_or_retry: 0,
  },
  deliveries: [
    {
      id: 123,
      event_name: "first_workout_completed",
      occurred_at: "2026-07-26T18:30:00Z",
      created_at: "2026-07-26T18:29:00Z",
      user: {
        id: 7,
        admin_display_id: "EH-000007",
        name: "Ana Souza",
        display_name: "Ana Souza",
        email: "ana@example.com",
      },
      channels: ["push"],
      destination: "push-progress",
      delivery_status: "accepted_by_make",
      attempt_count: 1,
      http_status: 202,
      make_status: "routed",
    },
  ],
  total: 1,
  page: 1,
  per: 25,
};

describe("EventDeliveriesPage", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mockGet.mockImplementation((path: string) => {
      if (path === "/api/v1/admin/analytics/event_deliveries/123") {
        return Promise.resolve({
          delivery: {
            ...listResponse.deliveries[0],
            source: "spec",
            first_attempt_at: "2026-07-26T18:29:30Z",
            last_attempt_at: "2026-07-26T18:29:31Z",
            next_retry_at: null,
            delivered_to_provider_at: "2026-07-26T18:29:31Z",
            response_body: "{\"ok\":true}",
            error_class: null,
            error_message: null,
            delivery_duration_ms: 120,
            idempotency_key: "first_workout_completed:7:123",
            make_execution_id: "exec-123",
            make_callback_at: "2026-07-26T18:31:00Z",
            make_processing_message: "Roteado",
            payload: { event_name: "first_workout_completed" },
            metadata: { safe: true },
          },
        });
      }
      if (path.startsWith("/api/v1/admin/analytics/event_deliveries")) {
        return Promise.resolve(listResponse);
      }
      return Promise.reject(new Error(`unexpected path ${path}`));
    });
  });

  it("renders deliveries and opens the read-only detail", async () => {
    const user = userEvent.setup();

    render(<EventDeliveriesPage />);

    await waitFor(() => {
      expect(screen.getByText("Log de eventos e entregas")).toBeInTheDocument();
      expect(screen.getByText("first_workout_completed")).toBeInTheDocument();
      expect(screen.getAllByText("Aceito pelo Make").length).toBeGreaterThan(0);
    });

    await user.click(screen.getByRole("button", { name: "#123" }));

    await waitFor(() => {
      expect(mockGet).toHaveBeenCalledWith("/api/v1/admin/analytics/event_deliveries/123");
      expect(screen.getByText("Payload enviado")).toBeInTheDocument();
      expect(screen.getAllByText(/first_workout_completed/).length).toBeGreaterThan(0);
    });
  });

  it("sends filters to the admin endpoint", async () => {
    render(<EventDeliveriesPage />);

    await waitFor(() => expect(screen.getByLabelText("Evento")).toBeInTheDocument());

    fireEvent.change(screen.getByLabelText("Evento"), { target: { value: "inactive" } });

    await waitFor(() => {
      const lastCall = mockGet.mock.calls.at(-1)?.[0] as string;
      expect(lastCall).toContain("event_name=inactive");
    });
  });
});

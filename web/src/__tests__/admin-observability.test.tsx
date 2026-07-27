import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi, beforeEach } from "vitest";
import ObservabilityPage from "@/app/(app)/admin/observability/page";
import { CARD_ORDER, ObservabilityPayload } from "@/app/(app)/admin/observability/types";

const mockGet = vi.hoisted(() => vi.fn());
const mockPost = vi.hoisted(() => vi.fn());
const mockReplace = vi.hoisted(() => vi.fn());

vi.mock("@/shared/lib/api", () => ({
  api: { get: mockGet, post: mockPost },
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: mockReplace, push: vi.fn() }),
}));

vi.mock("@/features/auth/auth-context", () => ({
  useAuth: () => ({ user: { id: 1, admin: true }, loading: false }),
}));

function card(key: string, overrides: Record<string, unknown> = {}) {
  return {
    key,
    title: key,
    status: "healthy",
    value: 0.85,
    unit: "ratio",
    headline: "85,0%",
    sample_size: 120,
    reference_value: null,
    threshold_value: 0.5,
    window: { started_at: null, ended_at: null, label: "últimas 24h" },
    definition: "definição",
    explanation: "tudo certo",
    updated_at: "2026-07-27T10:00:00Z",
    metrics: [],
    incident_ids: [],
    ...overrides,
  };
}

const payload: ObservabilityPayload = {
  generated_at: "2026-07-27T10:00:00Z",
  range: "24h",
  overall_status: "warning",
  cards: Object.fromEntries(CARD_ORDER.map((key) => [key, card(key)])),
  incidents: [
    {
      id: 7,
      source: "internal_check",
      check_key: "android_registration_conversion",
      title: "queda de cadastro",
      description: "conversão abaixo do piso",
      severity: "critical",
      status: "open",
      current_value: 0.05,
      threshold_value: 0.15,
      dimensions: { build_group: "current" },
      first_detected_at: "2026-07-27T08:00:00Z",
      last_detected_at: "2026-07-27T09:45:00Z",
      acknowledged_at: null,
      resolved_at: null,
      duration_seconds: 6300,
      occurrence_count: 7,
      notification_count: 1,
    },
  ],
  android_builds: [
    {
      app_version: "1.0.51",
      app_build: "51",
      build_group: "current",
      installations: 120,
      authenticated: 100,
      linked: 96,
      anonymous: 24,
      registrations: 90,
      google_auth_errors: 2,
      registration_rate: 0.8,
      linkage_rate: 0.8,
      sample_size: 120,
      status: "healthy",
    },
    {
      app_version: "1.0.52",
      app_build: "52",
      build_group: "current",
      installations: 3,
      authenticated: 0,
      linked: 0,
      anonymous: 3,
      registrations: 0,
      google_auth_errors: 0,
      registration_rate: null,
      linkage_rate: null,
      sample_size: 3,
      status: "insufficient_data",
    },
  ],
  heartbeats: [
    {
      key: "relationship_daily_job",
      category: "job",
      status: "healthy",
      expected_interval_seconds: 86400,
      last_started_at: "2026-07-27T03:00:00Z",
      last_succeeded_at: "2026-07-27T03:05:00Z",
      last_failed_at: null,
      last_duration_ms: 3200,
      seconds_since_success: 25000,
      consecutive_failures: 0,
      last_error_code: null,
    },
    {
      key: "bi_replica_refresh",
      category: "pipeline",
      status: "critical",
      expected_interval_seconds: 86400,
      last_started_at: null,
      last_succeeded_at: null,
      last_failed_at: null,
      last_duration_ms: null,
      seconds_since_success: null,
      consecutive_failures: 0,
      last_error_code: null,
    },
  ],
  thresholds: { min_android_sample: 10 },
  data_quality: {
    checks_total: 19,
    insufficient_data: 3,
    last_run_at: "2026-07-27T09:55:00Z",
    stale: false,
    notes: ["3 verificação(ões) sem amostra suficiente neste ciclo."],
  },
};

describe("admin observability page", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGet.mockResolvedValue(payload);
    mockPost.mockResolvedValue({});
  });

  it("renders exactly six cards", async () => {
    render(<ObservabilityPage />);

    await waitFor(() => expect(screen.getByTestId("observability-cards")).toBeInTheDocument());

    const cards = screen.getByTestId("observability-cards").querySelectorAll("[data-card-key]");
    expect(cards).toHaveLength(6);
  });

  it("renders the six cards in the documented order", async () => {
    render(<ObservabilityPage />);

    await waitFor(() => expect(screen.getByTestId("observability-cards")).toBeInTheDocument());

    const keys = Array.from(
      screen.getByTestId("observability-cards").querySelectorAll("[data-card-key]")
    ).map((el) => el.getAttribute("data-card-key"));

    expect(keys).toEqual(CARD_ORDER);
  });

  it("never renders a percentage for a card without a sample", async () => {
    mockGet.mockResolvedValue({
      ...payload,
      cards: {
        ...payload.cards,
        google_auth: card("google_auth", { status: "insufficient_data", value: null, headline: null }),
      },
    });

    render(<ObservabilityPage />);

    // Asserted on the value slot specifically: the card legitimately prints the
    // threshold ("limite 50%") elsewhere, and a substring check on the whole
    // card would match that.
    const value = await screen.findByTestId("card-value-google_auth");
    expect(value.textContent).toContain("amostra insuficiente");
    expect(value.textContent).not.toMatch(/%/);
  });

  it("labels a grey card as 'Sem amostra', not as healthy", async () => {
    mockGet.mockResolvedValue({
      ...payload,
      cards: {
        ...payload.cards,
        google_auth: card("google_auth", { status: "insufficient_data", value: null }),
      },
    });

    render(<ObservabilityPage />);

    const target = await screen.findByTestId("observability-card-google_auth");
    expect(target.textContent).toContain("Sem amostra");
    expect(target.textContent).not.toContain("Saudável");
  });

  it("shows a loading screen before data arrives", () => {
    mockGet.mockReturnValue(new Promise(() => {}));

    render(<ObservabilityPage />);

    expect(screen.queryByTestId("observability-cards")).not.toBeInTheDocument();
  });

  it("shows an error message when the request fails", async () => {
    mockGet.mockRejectedValue(new Error("boom"));

    render(<ObservabilityPage />);

    expect(await screen.findByText(/Não foi possível carregar o painel/i)).toBeInTheDocument();
  });

  it("renders the three tables", async () => {
    render(<ObservabilityPage />);

    expect(await screen.findByText("Incidentes")).toBeInTheDocument();
    expect(screen.getByText("Android por build")).toBeInTheDocument();
    expect(screen.getByText("Heartbeats")).toBeInTheDocument();
  });

  it("renders 'amostra insuficiente' instead of a rate for a low-sample build", async () => {
    render(<ObservabilityPage />);

    await screen.findByText("Android por build");
    const row = screen.getByText("1.0.52").closest("tr");

    expect(row?.textContent).toContain("amostra insuficiente");
    expect(row?.textContent).not.toContain("0%");
  });

  it("shows 'nunca' for a heartbeat that has never succeeded", async () => {
    render(<ObservabilityPage />);

    await screen.findByText("Heartbeats");
    const row = screen.getByText("bi_replica_refresh").closest("tr");

    expect(row?.textContent).toContain("nunca");
  });

  it("filters incidents by severity", async () => {
    const user = userEvent.setup();
    render(<ObservabilityPage />);

    expect(await screen.findByText("queda de cadastro")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Aviso" }));

    expect(screen.queryByText("queda de cadastro")).not.toBeInTheDocument();
  });

  it("acknowledges an incident through the API", async () => {
    const user = userEvent.setup();
    render(<ObservabilityPage />);

    await user.click(await screen.findByRole("button", { name: "Reconhecer" }));

    expect(mockPost).toHaveBeenCalledWith(
      "/api/v1/admin/observability/incidents/7/acknowledge",
      {}
    );
  });

  it("changes the android build window", async () => {
    const user = userEvent.setup();
    render(<ObservabilityPage />);

    await screen.findByText("Android por build");
    await user.click(screen.getByRole("button", { name: "7d" }));

    await waitFor(() =>
      expect(mockGet).toHaveBeenCalledWith(expect.stringContaining("range=7d"))
    );
  });

  it("shows the data-quality notes so a grey card is explained", async () => {
    render(<ObservabilityPage />);

    expect(await screen.findByText(/sem amostra suficiente neste ciclo/i)).toBeInTheDocument();
  });

  it("does not render any PII in the timeline search affordance", async () => {
    render(<ObservabilityPage />);

    await screen.findByText("Investigação por usuário ou instalação");
    expect(screen.getByText(/Nenhum e-mail, nome, token ou payload é exibido/i)).toBeInTheDocument();
    expect(document.body.textContent).not.toMatch(/@[a-z]+\.(com|br)/i);
  });
});

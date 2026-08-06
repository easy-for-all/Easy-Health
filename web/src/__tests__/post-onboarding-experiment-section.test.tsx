import { render, screen, waitFor } from "@testing-library/react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { PostOnboardingExperimentSection } from "@/app/(app)/admin/post-onboarding-experiment-section";

const { mockGet } = vi.hoisted(() => ({ mockGet: vi.fn() }));

vi.mock("@/shared/lib/api", () => ({ api: { get: mockGet } }));

function metric(numerator: number, denominator: number, status = "complete") {
  return {
    value: denominator === 0 ? 0 : Number(((numerator / denominator) * 100).toFixed(1)),
    numerator,
    denominator,
    sample_size: denominator,
    status,
    definition: "x",
  };
}

function payload(overrides: Record<string, unknown> = {}) {
  return {
    source: "product_analytics_events",
    generated_at: "2026-08-04T12:00:00Z",
    experiment_key: "android_post_onboarding_gate_v1",
    filters: { period: "since_start", build: null, audience: "external", variant: "all" },
    definitions: {
      experiment_key: "android_post_onboarding_gate_v1",
      min_build: 60,
      started_at: "2026-08-04T00:00:00Z",
      unit_note: "A unidade é installation_id distinto exposto.",
      window_note: "A janela de 24h é contada a partir do exposed_at de cada instalação.",
      readout_note: "O painel não declara vencedor.",
    },
    header: {
      status: "ativo",
      experiment_key: "android_post_onboarding_gate_v1",
      min_build: 60,
      started_at: "2026-08-04T00:00:00Z",
      expected_split: "50/50",
      assigned_installations: 240,
      exposed_installations: 200,
      distribution: [
        { variant: "account_gate", label: "Conta antes do plano", exposed: 100, share: metric(100, 200), sample_warning: "Leitura mais estável, ainda observacional" },
        { variant: "open_app", label: "Abre o app", exposed: 100, share: metric(100, 200), sample_warning: "Leitura mais estável, ainda observacional" },
      ],
      assigned_without_exposure: metric(40, 240),
    },
    metrics: [
      {
        key: "workout_started",
        label: "1º treino iniciado",
        unit: "installations",
        variants: {
          account_gate: { cumulative: metric(10, 100) },
          open_app: { cumulative: metric(25, 100) },
        },
        difference: { cumulative: { absolute_pp: 15.0, relative: 150.0 } },
      },
      {
        key: "time_to_first_workout",
        label: "Tempo até o 1º treino",
        unit: "seconds",
        variants: {
          account_gate: { p50_seconds: 3600, p90_seconds: 7200, sample_size: 10 },
          open_app: { p50_seconds: 300, p90_seconds: 900, sample_size: 25 },
        },
      },
    ],
    funnels: [
      { variant: "account_gate", label: "Conta antes do plano", exposed: 100, sample_warning: "Leitura mais estável, ainda observacional", stages: [{ key: "exposed", label: "Exposta", count: 100, conversion_from_exposed: metric(100, 100) }] },
      { variant: "open_app", label: "Abre o app", exposed: 100, sample_warning: "Leitura mais estável, ainda observacional", stages: [{ key: "exposed", label: "Exposta", count: 100, conversion_from_exposed: metric(100, 100) }] },
    ],
    last_stage: [
      { variant: "account_gate", label: "Conta antes do plano", buckets: [{ key: "exposed", label: "Exposta", count: 90 }] },
      { variant: "open_app", label: "Abre o app", buckets: [{ key: "exposed", label: "Exposta", count: 75 }] },
    ],
    guardrails: {
      events_missing_installation_id: 0,
      variant_disagreement: 0,
      generation_errors: 2,
      claim_failures: {},
      auth_failures: { account_gate: 3, open_app: 1 },
      no_plan_after_exposure: { account_gate: metric(60, 100), open_app: metric(20, 100) },
      hit_limit_rate: metric(5, 100),
      gate_seen_later_rate: metric(30, 100),
    },
    ...overrides,
  };
}

describe("PostOnboardingExperimentSection", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGet.mockResolvedValue(payload());
  });

  it("shows both variants side by side", async () => {
    render(<PostOnboardingExperimentSection />);

    // O rótulo aparece no card de distribuição, no funil e nos baldes.
    expect((await screen.findAllByText("Conta antes do plano")).length).toBeGreaterThan(0);
    expect(screen.getAllByText("Abre o app").length).toBeGreaterThan(0);
    expect(screen.getByText("10.0% (10/100)")).toBeInTheDocument();
    expect(screen.getByText("25.0% (25/100)")).toBeInTheDocument();
    expect(screen.getByText("+15 p.p.")).toBeInTheDocument();
  });

  // Um 0% afirmaria que ninguém converteu; "—" diz que não houve ninguém.
  it("renders an em dash, not 0%, when a variant has no coverage", async () => {
    const empty = payload();
    empty.metrics[0].variants.account_gate = { cumulative: metric(0, 0, "no_coverage") };
    empty.metrics[0].difference = { cumulative: { absolute_pp: null, relative: null } };
    mockGet.mockResolvedValue(empty);

    render(<PostOnboardingExperimentSection />);

    await screen.findByText("25.0% (25/100)");
    expect(screen.queryByText("0.0% (0/0)")).not.toBeInTheDocument();
    expect(screen.getAllByText("—").length).toBeGreaterThan(0);
  });

  // Se este aviso não aparecer, o painel apresenta como fato uma população que
  // não dá para reconstruir.
  it("puts the missing installation_id guardrail at the top when it is not zero", async () => {
    const broken = payload();
    broken.guardrails.events_missing_installation_id = 12;
    mockGet.mockResolvedValue(broken);

    render(<PostOnboardingExperimentSection />);

    expect(await screen.findByText(/12 evento\(s\) sem installation_id/)).toBeInTheDocument();
  });

  it("hides the data-quality banner when everything is clean", async () => {
    render(<PostOnboardingExperimentSection />);

    await screen.findAllByText("Conta antes do plano");
    expect(screen.queryByText(/sem installation_id\./)).not.toBeInTheDocument();
  });

  it("shows the sample warning and never declares a winner", async () => {
    const small = payload();
    small.header.distribution[0].sample_warning = "Amostra muito baixa — resultado apenas direcional";
    mockGet.mockResolvedValue(small);

    render(<PostOnboardingExperimentSection />);

    expect(await screen.findByText(/Amostra muito baixa/)).toBeInTheDocument();
    expect(screen.getByText(/não declara vencedor/)).toBeInTheDocument();
    expect(screen.queryByText(/vencedor:/i)).not.toBeInTheDocument();
  });

  // Tempo até o primeiro treino não é razão: mostrá-lo como porcentagem, ou
  // com uma "diferença relativa", seria mentir sobre o que a coluna significa.
  it("renders the timing metric as a duration, without a difference", async () => {
    render(<PostOnboardingExperimentSection />);

    expect(await screen.findByText("Tempo até o 1º treino (p50)")).toBeInTheDocument();
    expect(screen.getByText("1.0h")).toBeInTheDocument();
    expect(screen.getByText("5min")).toBeInTheDocument();
  });

  it("degrades to a message when the panel is unavailable", async () => {
    mockGet.mockRejectedValue(new Error("503"));

    render(<PostOnboardingExperimentSection />);

    await waitFor(() => expect(screen.getByText(/Painel indisponível/)).toBeInTheDocument());
  });
});

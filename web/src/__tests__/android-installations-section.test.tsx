import { render, screen, waitFor } from "@testing-library/react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { AndroidInstallationsSection } from "@/app/(app)/admin/android-installations-section";
import {
  type AndroidInstallationMetrics,
  type Metric,
  displayLabel,
  formatCount,
  formatRate,
  formatRateWithSample,
  hasDataQualityIssues,
  healthState,
} from "@/app/(app)/admin/android-installations-metrics";

const { mockGet } = vi.hoisted(() => ({ mockGet: vi.fn() }));

vi.mock("@/shared/lib/api", () => ({
  api: { get: mockGet },
}));

function metric(numerator: number, denominator: number): Metric {
  const value = denominator === 0 ? 0 : Math.round((numerator / denominator) * 1000) / 10;
  return {
    value,
    numerator,
    denominator,
    sample_size: denominator,
    status: denominator === 0 ? "no_coverage" : "complete",
    definition: "test_v1",
  };
}

const emptyMetrics: AndroidInstallationMetrics = {
  source: "app_installations",
  generated_at: "2026-07-26T12:00:00-03:00",
  definitions: {
    active_7d_since: "2026-07-19T12:00:00-03:00",
    active_30d_since: "2026-06-26T12:00:00-03:00",
    timeline_days: 14,
    healthy_link_rate: 95,
    attention_link_rate: 85,
    reconciliation_rate: "linked_at / first_authenticated_request_at",
  },
  overview: {
    total_installations: 0,
    linked_installations: 0,
    anonymous_installations: 0,
    authenticated_installations: 0,
    unique_linked_users: 0,
    users_with_multiple_installations: 0,
    active_installations_7d: 0,
    active_installations_30d: 0,
    new_installations_24h: 0,
    new_installations_7d: 0,
    new_installations_30d: 0,
    link_rate: metric(0, 0),
  },
  reconciliation: {
    observed_authenticated_installations: 0,
    link_attempted_installations: 0,
    linked_installations: 0,
    authenticated_unlinked_installations: 0,
    conflicts: 0,
    failures_by_code: {},
    link_rate: metric(0, 0),
  },
  data_quality: {
    linked_without_last_authenticated_at: 0,
    authenticated_at_without_user: 0,
    linked_without_linked_at: 0,
    linked_without_observed_request: 0,
    missing_app_build: 0,
    invalid_app_build: 0,
    missing_app_version: 0,
    missing_last_seen_at: 0,
  },
  adoption: {
    most_used_version: null,
    most_used_version_installations: 0,
    most_used_build: null,
    most_used_build_installations: 0,
    latest_build: null,
    latest_build_installations: 0,
    latest_build_share: metric(0, 0),
  },
  health_timeline: [],
  operational_health: [],
  installation_provenance: { registered_live: 0, backfilled: 0, coverage: metric(0, 0) },
  push: { permission_granted: 0, push_enabled: 0, valid_fcm_tokens: 0 },
  analytics_pipeline: {
    android_events_total: 0,
    android_events_7d: 0,
    installations_with_session: 0,
    last_event_at: null,
  },
  google_play: { configured: false, official_installs: null, last_synced_at: null, source: null },
  versions: [],
  manufacturers: [],
  device_models: [],
  operating_system_versions: [],
  user_funnel: [],
};

function withData(overrides: Partial<AndroidInstallationMetrics> = {}): AndroidInstallationMetrics {
  return { ...emptyMetrics, ...overrides };
}

function renderWith(payload: AndroidInstallationMetrics) {
  mockGet.mockResolvedValueOnce(payload);
  return render(<AndroidInstallationsSection />);
}

beforeEach(() => {
  mockGet.mockReset();
});

describe("AndroidInstallationsSection", () => {
  it("shows a loading state before the payload arrives", () => {
    mockGet.mockReturnValueOnce(new Promise(() => {}));
    render(<AndroidInstallationsSection />);

    expect(screen.getByText("Carregando…")).toBeInTheDocument();
  });

  // The section used to vanish silently on error (return null).
  it("shows an error message instead of disappearing", async () => {
    mockGet.mockRejectedValueOnce(new Error("boom"));
    render(<AndroidInstallationsSection />);

    expect(await screen.findByText(/Não foi possível carregar as métricas/i)).toBeInTheDocument();
    expect(screen.getByText("App Android")).toBeInTheDocument();
  });

  it("renders an empty base without NaN or undefined", async () => {
    const { container } = renderWith(emptyMetrics);

    await screen.findByText("Instalações Android registradas");
    expect(container.textContent).not.toMatch(/NaN|undefined/);
    expect(screen.getByText("Nenhuma inconsistência detectada.")).toBeInTheDocument();
    expect(screen.getByText("Nenhuma requisição autenticada observada no período.")).toBeInTheDocument();
  });

  it("renders the overview cards with installation and user counts apart", async () => {
    renderWith(
      withData({
        overview: {
          ...emptyMetrics.overview,
          total_installations: 12,
          linked_installations: 10,
          anonymous_installations: 2,
          unique_linked_users: 7,
          active_installations_7d: 5,
          active_installations_30d: 9,
          link_rate: metric(10, 12),
        },
      }),
    );

    await screen.findByText("Instalações Android registradas");
    expect(screen.getByText("12")).toBeInTheDocument();
    expect(screen.getByText("Usuários Android únicos")).toBeInTheDocument();
    expect(screen.getByText("7")).toBeInTheDocument();
    expect(screen.getByText("Instalações ainda anônimas")).toBeInTheDocument();
  });

  it("renders reconciliation health from observed authenticated requests", async () => {
    renderWith(
      withData({
        reconciliation: {
          ...emptyMetrics.reconciliation,
          observed_authenticated_installations: 3,
          linked_installations: 3,
          link_rate: metric(3, 3),
        },
      }),
    );

    expect(await screen.findByText("Reconciliação")).toBeInTheDocument();
    expect(screen.getByText("100%")).toBeInTheDocument();
    expect(screen.getByText("Saudável")).toBeInTheDocument();
    // A rate is never shown without its sample.
    expect(screen.getByText(/3 de 3 instalações observadas autenticadas/)).toBeInTheDocument();
  });

  it("flags an attention link rate", async () => {
    renderWith(
      withData({
        reconciliation: {
          ...emptyMetrics.reconciliation,
          observed_authenticated_installations: 10,
          linked_installations: 9,
          link_rate: metric(9, 10),
        },
      }),
    );

    expect(await screen.findByText("Atenção")).toBeInTheDocument();
  });

  it("flags a critical link rate", async () => {
    renderWith(
      withData({
        reconciliation: {
          ...emptyMetrics.reconciliation,
          observed_authenticated_installations: 10,
          linked_installations: 5,
          link_rate: metric(5, 10),
        },
      }),
    );

    expect(await screen.findByText("Crítico")).toBeInTheDocument();
  });

  it("shows 'sem dados' and no percentage when there is no observed authenticated sample", async () => {
    renderWith(emptyMetrics);

    expect(await screen.findByText("Sem dados")).toBeInTheDocument();
    expect(screen.getByText(/sem instalações observadas autenticadas nesta faixa ainda/)).toBeInTheDocument();
  });

  it("treats build as descriptive metadata, not reconciliation eligibility", async () => {
    const { container } = renderWith(emptyMetrics);

    await screen.findByText("Adoção de versão");
    expect(container.textContent).toMatch(/build é dimensão descritiva/i);
    expect(container.textContent).not.toMatch(/build 45\+/i);
  });

  it("lists data quality issues when they exist", async () => {
    renderWith(
      withData({
        data_quality: { ...emptyMetrics.data_quality, invalid_app_build: 3, missing_app_version: 1 },
      }),
    );

    expect(await screen.findByText("build inválido")).toBeInTheDocument();
    expect(screen.queryByText("Nenhuma inconsistência detectada.")).not.toBeInTheDocument();
  });

  it("renders the versions table ordered as received", async () => {
    renderWith(
      withData({
        versions: [
          {
            app_version: "1.0.45",
            app_build: "45",
            build_number: 45,
            total_installations: 3,
            linked_installations: 3,
            anonymous_installations: 0,
            active_installations_7d: 3,
            link_rate: metric(3, 3),
          },
          {
            app_version: null,
            app_build: null,
            build_number: null,
            total_installations: 1,
            linked_installations: 0,
            anonymous_installations: 1,
            active_installations_7d: 0,
            link_rate: metric(0, 1),
          },
        ],
      }),
    );

    expect(await screen.findByText("1.0.45")).toBeInTheDocument();
    expect(screen.getAllByText("não informado").length).toBeGreaterThan(0);
  });

  it("labels blank manufacturers and Android versions as 'não informado'", async () => {
    renderWith(
      withData({
        manufacturers: [
          { manufacturer: null, total_installations: 2, linked_installations: 1, active_installations_30d: 2 },
        ],
        operating_system_versions: [{ operating_system_version: null, total_installations: 2 }],
        device_models: [
          { manufacturer: "samsung", device_model: "SM-A125M", total_installations: 2, active_installations_30d: 1 },
        ],
      }),
    );

    await screen.findByText("Dispositivos");
    expect(screen.getAllByText("não informado").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("SM-A125M")).toBeInTheDocument();
  });

  it("renders the daily timeline newest first", async () => {
    renderWith(
      withData({
        health_timeline: [
          {
            date: "2026-07-26",
            observed_authenticated_installations: 2,
            linked_installations: 2,
            link_rate: metric(2, 2),
          },
          {
            date: "2026-07-25",
            observed_authenticated_installations: 4,
            linked_installations: 2,
            link_rate: metric(2, 4),
          },
        ],
      }),
    );

    await screen.findByText("Vínculo por dia");
    expect(screen.getByText("50%")).toBeInTheDocument();
  });

  it("never paints an unknown component as healthy", async () => {
    renderWith(
      withData({
        operational_health: [
          { key: "tracking", label: "Tracking Android", status: "ok", detail: "3 vistas em 24h" },
          { key: "push", label: "Push", status: "unknown", detail: "nenhum token ativo" },
        ],
      }),
    );

    await screen.findByText("Saúde operacional");
    expect(screen.getByText("sem sinal")).toBeInTheDocument();
    expect(screen.getByText("Tracking Android")).toBeInTheDocument();
  });

  it("shows the Google Play block as not integrated, without inventing a number", async () => {
    renderWith(emptyMetrics);

    await screen.findByText("Google Play");
    expect(screen.getByText("não integrado")).toBeInTheDocument();
    expect(screen.getByText(/vem da Play Console e ainda não é sincronizado/i)).toBeInTheDocument();
  });

  it("states that installations are not Google Play downloads", async () => {
    const { container } = renderWith(emptyMetrics);

    await screen.findByText("Instalações Android registradas");
    expect(container.textContent).toMatch(/Instalações ≠ dispositivos ≠ usuários ≠ sessões ≠ downloads da Google Play/);
  });

  it("requests the admin metrics endpoint", async () => {
    renderWith(emptyMetrics);

    await waitFor(() =>
      expect(mockGet).toHaveBeenCalledWith("/api/v1/admin/analytics/android_installations"),
    );
  });
});

describe("android installation metric helpers", () => {
  it("classifies link-rate health against the shared thresholds", () => {
    expect(healthState(metric(100, 100))).toBe("healthy");
    expect(healthState(metric(95, 100))).toBe("healthy");
    expect(healthState(metric(90, 100))).toBe("attention");
    expect(healthState(metric(50, 100))).toBe("critical");
    expect(healthState(metric(0, 0))).toBe("no_data");
    expect(healthState(undefined)).toBe("no_data");
  });

  it("never renders NaN for an empty sample", () => {
    expect(formatRate(metric(0, 0))).toBe("—");
    expect(formatRate(undefined)).toBe("—");
    expect(formatCount(Number.NaN)).toBe("—");
    expect(formatCount(undefined)).toBe("—");
    expect(formatCount(1234)).toBe("1.234");
  });

  it("always pairs a rate with its sample size", () => {
    expect(formatRateWithSample(metric(3, 3))).toBe("100% — 3 de 3 instalações");
    expect(formatRateWithSample(metric(0, 0))).toBe("sem instalações nesta faixa ainda");
  });

  it("labels blank grouping values without touching the data", () => {
    expect(displayLabel(null)).toBe("não informado");
    expect(displayLabel("")).toBe("não informado");
    expect(displayLabel("   ")).toBe("não informado");
    expect(displayLabel("samsung")).toBe("samsung");
    expect(displayLabel(45)).toBe("45");
  });

  it("detects data quality issues only when a counter is positive", () => {
    expect(hasDataQualityIssues(emptyMetrics.data_quality)).toBe(false);
    expect(hasDataQualityIssues({ ...emptyMetrics.data_quality, missing_app_build: 1 })).toBe(true);
  });
});

import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { AndroidFunnelSection } from "@/app/(app)/admin/android-funnel-section";
import {
  type AndroidFunnelPayload,
  type FunnelInstallationsPayload,
  type Metric,
  formatConversion,
  funnelQuery,
  shortInstallationId,
} from "@/app/(app)/admin/android-funnel-metrics";

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
    definition: "android_prelaunch_funnel_step_v1",
  };
}

function step(key: string, label: string, count: number, previous: number, cohort: number) {
  return {
    key,
    label,
    unit: "installations" as const,
    count,
    conversion_from_previous: metric(count, previous),
    conversion_from_cohort: metric(count, cohort),
  };
}

const payload: AndroidFunnelPayload = {
  source: "app_installations + product_analytics_events",
  generated_at: "2026-08-01T10:00:00-03:00",
  filters: { period: "since_instrumentation", build: null, audience: "external" },
  definitions: {
    min_instrumented_build: 51,
    period: "since_instrumentation",
    window_start: null,
    window_end: null,
    stage_definitions: [],
    bucket_order: [],
    instrumentation_note:
      "Funil detalhado disponível somente após a ativação da instrumentação pré-auth, a partir do build 51.",
    unit_note: "A unidade de cada etapa é installation_id distinto.",
    anonymous_classification_note: "Instalação sem usuário é contada como externa.",
    conflict_note: "installation_link_failed com conflict indica um aparelho já vinculado a outra conta.",
  },
  cohort: { installations: 100, excluded: { missing_or_invalid_build: 4 } },
  available_builds: [53, 51],
  steps: [
    { key: "installations", label: "Instalações observadas", unit: "installations", count: 100 },
    step("first_open", "First open", 95, 100, 100),
    step("session_started", "Session started", 94, 95, 100),
    step("entry_viewed", "Entrada visualizada", 92, 94, 100),
    step("auth_screen", "Tela de autenticação", 20, 92, 100),
    step("auth_choice", "Escolheu login/cadastro", 8, 20, 100),
    step("auth_provider", "Tentou autenticar", 7, 8, 100),
    step("auth_client", "Auth iniciada no cliente", 6, 7, 100),
    step("auth_api", "Auth chegou à API", 5, 6, 100),
    step("auth_done", "Auth concluída", 4, 5, 100),
    {
      key: "android_users",
      label: "Usuários Android criados",
      unit: "users",
      count: 3,
      note: "Métrica de usuários, não de instalações.",
    },
    step("linked", "Instalação vinculada", 2, 4, 100),
  ],
  biggest_drop: {
    from_key: "entry_viewed",
    from_label: "Entrada visualizada",
    to_key: "auth_screen",
    to_label: "Tela de autenticação",
    lost: 72,
    drop_rate: metric(72, 92),
  },
  stage_buckets: [
    { key: "no_events", label: "Sem evento do funil", count: 1 },
    { key: "stopped_first_open", label: "Parou após first open", count: 1 },
    { key: "stopped_session_started", label: "Parou após iniciar sessão", count: 2 },
    { key: "stopped_entry_viewed", label: "Parou após a entrada", count: 72 },
    { key: "stopped_auth_done", label: "Autenticou e não vinculou", count: 2 },
    { key: "completed", label: "Vinculada", count: 2 },
  ],
  link_failures: { user_conflict: 2 },
};

const installations: FunnelInstallationsPayload = {
  stage: "stopped_session_started",
  label: "Parou após iniciar sessão",
  total: 2,
  page: 1,
  per: 50,
  installations: [
    {
      installation_id: "6f1c2f70-3f6a-4a1c-9f0b-2b7c8d9e0f11",
      created_at: "2026-07-30T10:00:00Z",
      first_seen_at: "2026-07-30T10:00:00Z",
      last_seen_at: "2026-07-30T10:05:00Z",
      app_version: "1.0.51",
      app_build: "51",
      device_manufacturer: "samsung",
      device_model: "SM-A155M",
      operating_system: "android",
      operating_system_version: "14",
      last_stage: "stopped_session_started",
      last_stage_label: "Parou após iniciar sessão",
      last_event_name: "session_started",
      last_event_at: "2026-07-30T10:05:00Z",
      linked: false,
      link_result: null,
      last_link_failure_code: null,
      link_attempts_count: 0,
      user_id: null,
      email: null,
    },
  ],
};

describe("AndroidFunnelSection", () => {
  beforeEach(() => {
    mockGet.mockReset();
    mockGet.mockImplementation((path: string) => {
      if (path.includes("/android_funnel/installations")) return Promise.resolve(installations);
      return Promise.resolve(payload);
    });
  });

  it("renders every step including session started", async () => {
    render(<AndroidFunnelSection />);

    await screen.findByText("Instalações observadas");
    for (const label of [
      "First open",
      "Session started",
      "Entrada visualizada",
      "Tela de autenticação",
      "Escolheu login/cadastro",
      "Tentou autenticar",
      "Auth iniciada no cliente",
      "Auth chegou à API",
      "Auth concluída",
      "Usuários Android criados",
      "Instalação vinculada",
    ]) {
      expect(screen.getByText(label)).toBeInTheDocument();
    }
  });

  it("marks the users step as a different unit", async () => {
    render(<AndroidFunnelSection />);

    const row = (await screen.findByText("Usuários Android criados")).closest("tr")!;
    expect(within(row).getByText("usuários")).toBeInTheDocument();
    // A user count has no conversion against an installation count.
    expect(within(row).getAllByText("—")).toHaveLength(2);
  });

  it("shows the biggest observed drop without claiming a cause", async () => {
    render(<AndroidFunnelSection />);

    await screen.findByText("Maior abandono observado");
    expect(screen.getByText("Entrada visualizada → Tela de autenticação")).toBeInTheDocument();
    expect(screen.getByText(/72 instalações não avançaram/)).toBeInTheDocument();
    expect(screen.queryByText(/causa/i)).not.toBeInTheDocument();
  });

  it("reports installations excluded for an invalid build", async () => {
    render(<AndroidFunnelSection />);

    expect(
      await screen.findByText(/4 instalação\(ões\) fora do funil por build ausente ou inválido/),
    ).toBeInTheDocument();
  });

  it("refetches when a filter changes", async () => {
    render(<AndroidFunnelSection />);
    await screen.findByText("Instalações observadas");

    await userEvent.click(screen.getByRole("button", { name: "Todos" }));

    await waitFor(() => {
      expect(mockGet).toHaveBeenCalledWith(expect.stringContaining("audience=all"));
    });
  });

  it("loads the list only when a bucket is opened and links to the timeline", async () => {
    render(<AndroidFunnelSection />);
    await screen.findByText("Instalações observadas");

    expect(mockGet).not.toHaveBeenCalledWith(expect.stringContaining("/android_funnel/installations"));

    await userEvent.click(screen.getByText("Parou após iniciar sessão"));

    const link = await screen.findByRole("link", {
      name: shortInstallationId(installations.installations[0].installation_id),
    });
    expect(link).toHaveAttribute(
      "href",
      `/admin/observability?installation_id=${installations.installations[0].installation_id}`,
    );
  });

  it("degrades to a message when the endpoint fails", async () => {
    mockGet.mockRejectedValue(new Error("boom"));
    render(<AndroidFunnelSection />);

    expect(await screen.findByText("Funil indisponível no momento.")).toBeInTheDocument();
  });
});

describe("funnel helpers", () => {
  it("never renders a percentage without a denominator", () => {
    expect(formatConversion(metric(0, 0))).toBe("—");
    expect(formatConversion(undefined)).toBe("—");
    expect(formatConversion(metric(1, 4))).toBe("25%");
  });

  it("omits an empty build from the query", () => {
    expect(funnelQuery({ period: "7d", build: "", audience: "external" })).toBe(
      "period=7d&audience=external",
    );
    expect(funnelQuery({ period: "7d", build: "53", audience: "all" })).toBe(
      "period=7d&audience=all&build=53",
    );
  });

  it("abbreviates long installation ids only", () => {
    expect(shortInstallationId("short-id")).toBe("short-id");
    expect(shortInstallationId("6f1c2f70-3f6a-4a1c-9f0b-2b7c8d9e0f11")).toBe("6f1c2f70…0f11");
  });
});

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  EXPERIMENT_KEY,
  fnv1a,
  variantForInstallation,
  resolveVariant,
  recordAssignment,
  exposeOnce,
  hasBeenExposed,
  isEligible,
} from "@/features/experiments/android-post-onboarding-gate";

const { mockIsNativeApp, mockInstallationId, mockBuildNumber, mockTrackEvent, mockTrackOnce, mockPost } = vi.hoisted(
  () => ({
    mockIsNativeApp: vi.fn(() => true),
    mockInstallationId: vi.fn<() => string | undefined>(() => "install-1"),
    mockBuildNumber: vi.fn<() => string | undefined>(() => "60"),
    mockTrackEvent: vi.fn(),
    mockTrackOnce: vi.fn(),
    mockPost: vi.fn(() => Promise.resolve({ status: "assigned", variant: "account_gate" })),
  })
);

vi.mock("@/shared/lib/analytics/context", () => ({
  isNativeApp: () => mockIsNativeApp(),
  getCachedInstallationId: () => mockInstallationId(),
  getAnalyticsContext: () => ({ build_number: mockBuildNumber() }),
}));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: mockTrackEvent,
  trackOnce: mockTrackOnce,
}));

vi.mock("@/shared/lib/api", () => ({ api: { post: mockPost } }));

function enableExperiment() {
  vi.stubEnv("NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED", "true");
}

describe("variant hashing", () => {
  // Vetores padrão do FNV-1a 32 bits. Não são decoração: se alguém trocar a
  // função de hash com o experimento no ar, TODA instalação já atribuída é
  // rebucketizada e as duas variantes passam a medir populações misturadas.
  it("matches the published FNV-1a 32-bit vectors", () => {
    expect(fnv1a("")).toBe(0x811c9dc5);
    expect(fnv1a("a")).toBe(0xe40c292c);
    expect(fnv1a("foobar")).toBe(0xbf9cf968);
  });

  it("gives the same installation the same variant every time", () => {
    const first = variantForInstallation("install-abc");
    for (let i = 0; i < 50; i++) expect(variantForInstallation("install-abc")).toBe(first);
  });

  it("splits close to 50/50 across many installations", () => {
    let openApp = 0;
    const total = 10_000;
    for (let i = 0; i < total; i++) {
      if (variantForInstallation(`installation-${i}`) === "open_app") openApp += 1;
    }

    const share = openApp / total;
    expect(share).toBeGreaterThan(0.48);
    expect(share).toBeLessThan(0.52);
  });
});

describe("eligibility", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    mockIsNativeApp.mockReturnValue(true);
    mockInstallationId.mockReturnValue("install-1");
    mockBuildNumber.mockReturnValue("60");
  });

  afterEach(() => vi.unstubAllEnvs());

  it("is off unless the flag is explicitly true", () => {
    // Default-OFF: um servidor onde a env nunca foi setada precisa entregar o
    // fluxo provado, não o que ainda não foi medido.
    expect(isEligible({ authenticated: false })).toBe(false);

    vi.stubEnv("NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED", "1");
    expect(isEligible({ authenticated: false })).toBe(false);

    enableExperiment();
    expect(isEligible({ authenticated: false })).toBe(true);
  });

  it("excludes web, PWA and authenticated users", () => {
    enableExperiment();

    mockIsNativeApp.mockReturnValue(false);
    expect(isEligible({ authenticated: false })).toBe(false);

    mockIsNativeApp.mockReturnValue(true);
    expect(isEligible({ authenticated: true })).toBe(false);
  });

  it("excludes builds below the cut and builds it cannot read", () => {
    enableExperiment();
    vi.stubEnv("NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_MIN_BUILD", "60");

    mockBuildNumber.mockReturnValue("59");
    expect(isEligible({ authenticated: false })).toBe(false);

    mockBuildNumber.mockReturnValue("60");
    expect(isEligible({ authenticated: false })).toBe(true);

    // Build desconhecido fica de fora: não há como afirmar que emite os eventos.
    mockBuildNumber.mockReturnValue(undefined);
    expect(isEligible({ authenticated: false })).toBe(false);
  });

  it("excludes anything before the start timestamp", () => {
    enableExperiment();
    vi.stubEnv("NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_STARTED_AT", "2999-01-01T00:00:00Z");
    expect(isEligible({ authenticated: false })).toBe(false);

    vi.stubEnv("NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_STARTED_AT", "2020-01-01T00:00:00Z");
    expect(isEligible({ authenticated: false })).toBe(true);
  });

  it("excludes an installation without a resolved id", () => {
    enableExperiment();
    mockInstallationId.mockReturnValue(undefined);
    expect(isEligible({ authenticated: false })).toBe(false);
  });
});

describe("assignment persistence", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    mockIsNativeApp.mockReturnValue(true);
    mockInstallationId.mockReturnValue("install-1");
    mockBuildNumber.mockReturnValue("60");
    enableExperiment();
  });

  afterEach(() => vi.unstubAllEnvs());

  it("keeps the variant across reloads", () => {
    const first = resolveVariant({ authenticated: false });
    expect(first.eligible).toBe(true);
    expect(first.assigned).toBe(true);

    const second = resolveVariant({ authenticated: false });
    expect(second.variant).toBe(first.variant);
    // Só a PRIMEIRA vez conta como atribuição; senão experiment_assigned seria
    // reemitido a cada abertura do app e a contagem de atribuídas explodiria.
    expect(second.assigned).toBe(false);
  });

  // O diretório do WebView entra no Android Auto Backup, então um restore pode
  // devolver a atribuição da instalação ANTERIOR. Sem descartar, as duas
  // instalações apareceriam no painel como uma só.
  it("discards an assignment that belongs to another installation", () => {
    resolveVariant({ authenticated: false });

    mockInstallationId.mockReturnValue("install-2");
    const restored = resolveVariant({ authenticated: false });

    expect(restored.assigned).toBe(true);
    expect(restored.variant).toBe(variantForInstallation("install-2"));
    const stored = JSON.parse(window.localStorage.getItem("eh_experiments") ?? "{}");
    expect(stored[EXPERIMENT_KEY].installation_id).toBe("install-2");
  });

  it("persists nothing and emits nothing when ineligible", () => {
    vi.stubEnv("NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED", "false");

    const decision = resolveVariant({ authenticated: false });

    expect(decision).toEqual({ variant: "account_gate", eligible: false, assigned: false });
    expect(window.localStorage.getItem("eh_experiments")).toBeNull();
    expect(mockTrackEvent).not.toHaveBeenCalled();
    expect(mockTrackOnce).not.toHaveBeenCalled();
  });

  it("adopts the stored variant when the backend disagrees", async () => {
    mockPost.mockResolvedValue({ status: "conflict", variant: "open_app" });

    recordAssignment("account_gate");
    await vi.waitFor(() => {
      const stored = JSON.parse(window.localStorage.getItem("eh_experiments") ?? "{}");
      // O banco é o desempate: a linha armazenada é a que já teve exposição medida.
      expect(stored[EXPERIMENT_KEY]?.variant).toBe("open_app");
    });
  });

  it("keeps the local variant when the assignment write fails", async () => {
    resolveVariant({ authenticated: false });
    const before = window.localStorage.getItem("eh_experiments");
    mockPost.mockRejectedValue(new Error("offline"));

    recordAssignment("account_gate");
    await Promise.resolve();

    expect(window.localStorage.getItem("eh_experiments")).toBe(before);
  });
});

describe("exposure", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    mockIsNativeApp.mockReturnValue(true);
    mockInstallationId.mockReturnValue("install-1");
    enableExperiment();
  });

  afterEach(() => vi.unstubAllEnvs());

  it("marks the installation so a reload does not re-expose it", () => {
    expect(hasBeenExposed()).toBe(false);

    exposeOnce("open_app");
    expect(mockTrackOnce).toHaveBeenCalledTimes(1);
    expect(hasBeenExposed()).toBe(true);

    // Segunda passagem simula reload / volta da Activity do Google: o Set do
    // trackOnce já não existe, e é o marcador persistido que segura.
    exposeOnce("open_app");
    expect(mockTrackOnce).toHaveBeenCalledTimes(1);
  });

  it("carries no personal data", () => {
    exposeOnce("open_app");

    const [, , props] = mockTrackOnce.mock.calls[0];
    expect(Object.keys(props as object).sort()).toEqual(["experiment_key", "exposure_point", "variant"]);
  });
});

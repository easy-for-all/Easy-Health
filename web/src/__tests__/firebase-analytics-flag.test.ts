import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// A flag de build e o consentimento, exercitando firebase.ts DE VERDADE.
//
// Os outros testes de analytics mockam o wrapper (@/shared/lib/analytics/firebase),
// o que é certo para testar roteamento mas por construção não prova a leitura da
// env var — foi exatamente por isso que a produção ficou meses sem enviar evento
// nenhum com a suíte verde. Aqui a env var é real e quem está mockado é o plugin
// nativo, na fronteira.

const setEnabled = vi.fn();
const logEvent = vi.fn();

const FLAG = "NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED";

function firebasePluginMock() {
  return {
    FirebaseAnalytics: {
      setEnabled,
      logEvent,
      setCurrentScreen: vi.fn(),
      setUserId: vi.fn(),
      setUserProperty: vi.fn(),
    },
  };
}

// flag === undefined reproduz o servidor de produção antes da correção: a
// variável simplesmente não existia no momento do `next build`.
async function loadFirebase(opts: { native: boolean; flag?: string }) {
  vi.resetModules();
  if (opts.flag === undefined) delete process.env[FLAG];
  else process.env[FLAG] = opts.flag;

  vi.doMock("@capacitor/core", () => ({
    Capacitor: {
      getPlatform: () => (opts.native ? "android" : "web"),
      isNativePlatform: () => opts.native,
    },
  }));
  vi.doMock("@capacitor-firebase/analytics", firebasePluginMock);

  return await import("@/shared/lib/analytics/firebase");
}

describe("firebaseAnalyticsActive (flag de build)", () => {
  beforeEach(() => {
    setEnabled.mockClear();
    logEvent.mockClear();
  });

  afterEach(() => {
    delete process.env[FLAG];
    vi.doUnmock("@capacitor/core");
    vi.doUnmock("@capacitor-firebase/analytics");
    vi.resetModules();
  });

  it("ativa no Android nativo quando a flag é exatamente 'true'", async () => {
    const { firebaseAnalyticsActive } = await loadFirebase({ native: true, flag: "true" });
    expect(firebaseAnalyticsActive()).toBe(true);
  });

  // A regressão original: sem ARG no Dockerfile a variável chega undefined.
  it("fica inativa no Android quando a flag está ausente no build", async () => {
    const { firebaseAnalyticsActive } = await loadFirebase({ native: true });
    expect(firebaseAnalyticsActive()).toBe(false);
  });

  it("fica inativa no Android quando a flag é string vazia", async () => {
    const { firebaseAnalyticsActive } = await loadFirebase({ native: true, flag: "" });
    expect(firebaseAnalyticsActive()).toBe(false);
  });

  it("fica inativa no Android quando a flag é 'false' (kill switch)", async () => {
    const { firebaseAnalyticsActive } = await loadFirebase({ native: true, flag: "false" });
    expect(firebaseAnalyticsActive()).toBe(false);
  });

  // Na web quem mede é o GA4/gtag; o Firebase é no-op por design.
  it("fica inativa na web mesmo com a flag 'true'", async () => {
    const { firebaseAnalyticsActive } = await loadFirebase({ native: false, flag: "true" });
    expect(firebaseAnalyticsActive()).toBe(false);
  });

  it("só envia evento ao plugin quando está ativa", async () => {
    const off = await loadFirebase({ native: true });
    await off.logFirebaseEvent("workout_completed");
    expect(logEvent).not.toHaveBeenCalled();

    const on = await loadFirebase({ native: true, flag: "true" });
    await on.logFirebaseEvent("workout_completed");
    expect(logEvent).toHaveBeenCalledWith({ name: "workout_completed", params: {} });
  });
});

describe("initFirebase (consentimento com três estados)", () => {
  beforeEach(() => {
    setEnabled.mockClear();
  });

  afterEach(() => {
    delete process.env[FLAG];
    vi.doUnmock("@capacitor/core");
    vi.doUnmock("@capacitor-firebase/analytics");
    vi.resetModules();
  });

  // O ponto mais delicado desta correção. Não existe UI de consentimento, então
  // storedConsent() é null para todo mundo. Se null virasse setEnabled(false), o
  // valor persistiria em SharedPreferences no Android e desligaria até os eventos
  // automáticos (first_open, session_start) que hoje funcionam — ligar a flag
  // deixaria o tracking PIOR do que estava.
  it("sem decisão do usuário (null): NÃO toca no SDK", async () => {
    const { initFirebase } = await loadFirebase({ native: true, flag: "true" });
    await initFirebase(null);
    expect(setEnabled).not.toHaveBeenCalled();
  });

  it("consentimento negado explicitamente: desliga a coleta", async () => {
    const { initFirebase } = await loadFirebase({ native: true, flag: "true" });
    await initFirebase("denied");
    expect(setEnabled).toHaveBeenCalledWith({ enabled: false });
  });

  it("consentimento concedido: liga a coleta", async () => {
    const { initFirebase } = await loadFirebase({ native: true, flag: "true" });
    await initFirebase("granted");
    expect(setEnabled).toHaveBeenCalledWith({ enabled: true });
  });

  it("não toca no SDK quando a flag de build está desligada", async () => {
    const { initFirebase } = await loadFirebase({ native: true, flag: "false" });
    await initFirebase("granted");
    expect(setEnabled).not.toHaveBeenCalled();
  });

  it("não toca no SDK na web", async () => {
    const { initFirebase } = await loadFirebase({ native: false, flag: "true" });
    await initFirebase("granted");
    expect(setEnabled).not.toHaveBeenCalled();
  });

  // Uma decisão explícita posterior continua chegando ao SDK: o fix do null não
  // enfraqueceu o mecanismo de consentimento, que é o que updateConsent() chama.
  it("setFirebaseAnalyticsConsent continua espelhando a decisão do usuário", async () => {
    const { setFirebaseAnalyticsConsent } = await loadFirebase({ native: true, flag: "true" });
    await setFirebaseAnalyticsConsent(false);
    expect(setEnabled).toHaveBeenCalledWith({ enabled: false });

    setEnabled.mockClear();
    await setFirebaseAnalyticsConsent(true);
    expect(setEnabled).toHaveBeenCalledWith({ enabled: true });
  });
});

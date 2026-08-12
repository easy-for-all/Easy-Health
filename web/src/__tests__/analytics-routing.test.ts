import { describe, it, expect, beforeEach, vi, afterEach } from "vitest";

// Destination routing (anti-duplication). The rule that keeps Android from being
// double-counted once native Firebase Analytics is live: on native the event
// goes to Firebase ONLY and GA4 (gtag) is suppressed; on web GA4 still fires.

const logFirebaseEvent = vi.fn();
let firebaseActive = false;

async function loadIndex() {
  vi.resetModules();
  vi.doMock("./firebase", () => ({
    firebaseAnalyticsActive: () => firebaseActive,
    logFirebaseEvent,
    setFirebaseScreen: vi.fn(),
    setFirebaseUserId: vi.fn(),
  }));
  // firebase.ts lives beside index.ts; mock via the same relative id it imports.
  vi.doMock("@/shared/lib/analytics/firebase", () => ({
    firebaseAnalyticsActive: () => firebaseActive,
    logFirebaseEvent,
    setFirebaseScreen: vi.fn(),
    setFirebaseUserId: vi.fn(),
  }));
  return await import("@/shared/lib/analytics/index");
}

describe("event destination routing", () => {
  beforeEach(() => {
    logFirebaseEvent.mockClear();
    (window as unknown as { gtag: ReturnType<typeof vi.fn> }).gtag = vi.fn();
    process.env.NEXT_PUBLIC_APP_ENV = "production";
  });
  afterEach(() => {
    delete process.env.NEXT_PUBLIC_APP_ENV;
    vi.doUnmock("@/shared/lib/analytics/firebase");
  });

  it("web: sends to GA4 (gtag) and NOT to Firebase", async () => {
    firebaseActive = false;
    const { trackEvent } = await loadIndex();
    trackEvent("workout_started", { a: 1 });
    const gtag = (window as unknown as { gtag: ReturnType<typeof vi.fn> }).gtag;
    expect(gtag).toHaveBeenCalledWith("event", "workout_started", { a: 1 });
    expect(logFirebaseEvent).not.toHaveBeenCalled();
  });

  it("native with Firebase active: sends to Firebase and SUPPRESSES GA4", async () => {
    firebaseActive = true;
    const { trackEvent } = await loadIndex();
    trackEvent("workout_started", { a: 1 });
    const gtag = (window as unknown as { gtag: ReturnType<typeof vi.fn> }).gtag;
    expect(gtag).not.toHaveBeenCalled();
    expect(logFirebaseEvent).toHaveBeenCalledWith("workout_started", { a: 1 });
  });
});

// O bloco acima mocka firebaseAnalyticsActive, então prova a REGRA de roteamento
// mas não o que a decide. Ele ficou verde durante todo o período em que a
// produção não enviava evento nenhum, porque a causa raiz estava um nível abaixo:
// a flag de build. Este bloco fecha esse buraco — nada de firebase.ts é mockado,
// só o plugin nativo e a env var, e a asserção vai até FirebaseAnalytics.logEvent.

const nativeLogEvent = vi.fn();

const BUSINESS_EVENTS = [
  "signup_completed",
  "onboarding_completed",
  "workout_created",
  "workout_completed",
] as const;

async function loadIndexEndToEnd(opts: { native: boolean; flag?: string }) {
  vi.resetModules();
  if (opts.flag === undefined) delete process.env.NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED;
  else process.env.NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED = opts.flag;

  vi.doMock("@capacitor/core", () => ({
    Capacitor: {
      getPlatform: () => (opts.native ? "android" : "web"),
      isNativePlatform: () => opts.native,
    },
  }));
  vi.doMock("@capacitor-firebase/analytics", () => ({
    FirebaseAnalytics: {
      logEvent: nativeLogEvent,
      setEnabled: vi.fn(),
      setCurrentScreen: vi.fn(),
      setUserId: vi.fn(),
      setUserProperty: vi.fn(),
    },
  }));
  // O sink de backend é ortogonal ao roteamento GA4/Firebase e faria fetch real.
  vi.doMock("@/shared/lib/analytics/server", () => ({
    isServerEvent: () => false,
    enqueueServerEvent: vi.fn(),
    flushOnBackground: vi.fn(),
  }));

  return await import("@/shared/lib/analytics/index");
}

describe("routing end-to-end (env var real, plugin nativo mockado)", () => {
  beforeEach(() => {
    nativeLogEvent.mockClear();
    (window as unknown as { gtag: ReturnType<typeof vi.fn> }).gtag = vi.fn();
    process.env.NEXT_PUBLIC_APP_ENV = "production";
  });

  afterEach(() => {
    delete process.env.NEXT_PUBLIC_APP_ENV;
    delete process.env.NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED;
    vi.doUnmock("@capacitor/core");
    vi.doUnmock("@capacitor-firebase/analytics");
    vi.doUnmock("@/shared/lib/analytics/server");
    vi.resetModules();
  });

  it.each(BUSINESS_EVENTS)(
    "Android + flag true: %s chega em FirebaseAnalytics.logEvent e o gtag é suprimido",
    async (eventName) => {
      const { trackEvent } = await loadIndexEndToEnd({ native: true, flag: "true" });
      trackEvent(eventName, { source: "test" });

      // logFirebaseEvent resolve um import() dinâmico antes de chamar o plugin.
      await vi.waitFor(() =>
        expect(nativeLogEvent).toHaveBeenCalledWith({
          name: eventName,
          params: { source: "test" },
        })
      );
      expect((window as unknown as { gtag: ReturnType<typeof vi.fn> }).gtag).not.toHaveBeenCalled();
    }
  );

  it.each(BUSINESS_EVENTS)("web: %s continua indo para o GA4 e não para o Firebase", async (eventName) => {
    const { trackEvent } = await loadIndexEndToEnd({ native: false, flag: "true" });
    trackEvent(eventName, { source: "test" });

    expect((window as unknown as { gtag: ReturnType<typeof vi.fn> }).gtag).toHaveBeenCalledWith(
      "event",
      eventName,
      { source: "test" }
    );
    await new Promise((r) => setTimeout(r, 0));
    expect(nativeLogEvent).not.toHaveBeenCalled();
  });

  // O estado exato da produção antes desta correção.
  it("Android sem a flag no build: o evento não chega ao Firebase", async () => {
    const { trackEvent } = await loadIndexEndToEnd({ native: true });
    trackEvent("workout_completed", { source: "test" });

    await new Promise((r) => setTimeout(r, 0));
    expect(nativeLogEvent).not.toHaveBeenCalled();
  });
});

import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";

// The pre-auth funnel and the installation_id correlation, asserted on the
// payload that is actually POSTed to /api/v1/analytics/events — not on the
// helper calls. installation_id travels inside `properties` (no column, no
// migration), and the sendBeacon path carries no headers at all, so the body is
// the only thing that can be trusted to carry it.

vi.mock("@capacitor/core", () => ({
  Capacitor: { isNativePlatform: () => true, getPlatform: () => "android" },
}));

type SentEvent = {
  event_name: string;
  session_id: string;
  anonymous_id: string;
  properties: Record<string, unknown>;
};

async function drain(): Promise<SentEvent[]> {
  const { flush } = await import("@/shared/lib/analytics/server");
  await flush();
  const calls = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls;
  return calls.flatMap((call) => JSON.parse(String(call[1]?.body)).events as SentEvent[]);
}

describe("pre-auth funnel payload", () => {
  beforeEach(() => {
    process.env.NEXT_PUBLIC_APP_ENV = "production";
    window.localStorage.clear();
    window.sessionStorage.clear();
    vi.resetModules();
    globalThis.fetch = vi.fn(async () => ({ ok: true }) as Response) as typeof fetch;
  });

  afterEach(() => {
    delete process.env.NEXT_PUBLIC_APP_ENV;
    vi.restoreAllMocks();
  });

  it("persists every new pre-auth event to the backend", async () => {
    const { trackEvent } = await import("@/shared/lib/analytics");

    trackEvent("landing_page_viewed");
    trackEvent("auth_screen_viewed", { auth_screen: "sign_up" });
    trackEvent("signup_selected", { from: "landing" });
    trackEvent("login_selected", { from: "landing" });
    trackEvent("auth_provider_clicked", {
      provider: "google",
      auth_screen: "sign_up",
      intent: "sign_up",
      terms_accepted: true,
      source: "auth_screen",
    });
    trackEvent("social_login_started", { provider: "google", intent: "sign_up" });
    trackEvent("signup_started", { method: "email" });
    trackEvent("login_started", { method: "email" });
    trackEvent("auth_client_error", { stage: "google_plugin", error_code: "plugin_init_failed" });
    trackEvent("auth_api_error", { stage: "email_signup", http_status: 422 });

    const sent = await drain();
    const names = sent.map((e) => e.event_name);

    // Every one of these was ga4-only (or had no call site at all) before, which
    // is why the stretch between session_started and the API request was dark.
    expect(names).toEqual(
      expect.arrayContaining([
        "landing_page_viewed",
        "auth_screen_viewed",
        "signup_selected",
        "login_selected",
        "auth_provider_clicked",
        "social_login_started",
        "signup_started",
        "login_started",
        "auth_client_error",
        "auth_api_error",
      ])
    );
  });

  it("keeps the event properties that make the funnel readable", async () => {
    const { trackEvent } = await import("@/shared/lib/analytics");
    trackEvent("auth_screen_viewed", { auth_screen: "login" });
    trackEvent("auth_provider_clicked", {
      provider: "email",
      auth_screen: "login",
      intent: "login",
      source: "auth_screen",
    });
    trackEvent("auth_api_error", { stage: "email_login", http_status: 401 });

    const sent = await drain();
    const screen = sent.find((e) => e.event_name === "auth_screen_viewed");
    const providerClick = sent.find((e) => e.event_name === "auth_provider_clicked");
    const apiError = sent.find((e) => e.event_name === "auth_api_error");

    expect(screen?.properties.auth_screen).toBe("login");
    expect(providerClick?.properties.provider).toBe("email");
    expect(providerClick?.properties.auth_screen).toBe("login");
    expect(providerClick?.properties.intent).toBe("login");
    expect(providerClick?.properties.source).toBe("auth_screen");
    expect(providerClick?.properties).not.toHaveProperty("terms_accepted");
    expect(apiError?.properties.stage).toBe("email_login");
    expect(apiError?.properties.http_status).toBe(401);
  });

  it("attaches installation_id to the payload without replacing anonymous_id", async () => {
    const { setCachedInstallationId } = await import("@/shared/lib/analytics/context");
    setCachedInstallationId("install-xyz-789");

    const { trackEvent } = await import("@/shared/lib/analytics");
    trackEvent("auth_screen_viewed", { auth_screen: "login" });

    const [event] = await drain();
    expect(event.properties.installation_id).toBe("install-xyz-789");
    expect(event.anonymous_id).toBeTruthy();
    expect(event.anonymous_id).not.toBe("install-xyz-789");
    expect(event.session_id).toBeTruthy();
    expect(event.session_id).not.toBe("install-xyz-789");
  });

  it("omits installation_id rather than sending a placeholder when unknown", async () => {
    const { trackEvent } = await import("@/shared/lib/analytics");
    trackEvent("landing_page_viewed");

    const [event] = await drain();
    expect(event.properties).not.toHaveProperty("installation_id");
  });
});

describe("auth screen view guard", () => {
  beforeEach(() => {
    process.env.NEXT_PUBLIC_APP_ENV = "production";
    window.localStorage.clear();
    window.sessionStorage.clear();
    vi.resetModules();
    globalThis.fetch = vi.fn(async () => ({ ok: true }) as Response) as typeof fetch;
  });

  afterEach(() => {
    delete process.env.NEXT_PUBLIC_APP_ENV;
    vi.restoreAllMocks();
  });

  it("fires auth_screen_viewed once per screen even on a repeated mount", async () => {
    const { trackOnce } = await import("@/shared/lib/analytics");

    // What useAuthScreenView does; React Strict Mode invokes the effect twice.
    trackOnce("auth_screen_viewed:login", "auth_screen_viewed", { auth_screen: "login" });
    trackOnce("auth_screen_viewed:login", "auth_screen_viewed", { auth_screen: "login" });
    trackOnce("auth_screen_viewed:sign_up", "auth_screen_viewed", { auth_screen: "sign_up" });

    const sent = await drain();
    const views = sent.filter((e) => e.event_name === "auth_screen_viewed");

    expect(views).toHaveLength(2);
    expect(views.map((v) => v.properties.auth_screen).sort()).toEqual(["login", "sign_up"]);
  });
});

import { describe, it, expect, vi, afterEach } from "vitest";

// Guarda de release. App Store 2.5.2 (código remoto) e 4.2 (site empacotado)
// são as duas rejeições que o bundle local existe para evitar; um server.url
// que vaze para o IPA desfaz as duas de uma vez, e é o tipo de regressão que
// ninguém percebe até o build já estar submetido.
const ENV_KEYS = ["CAP_TARGET", "CAP_LIVE_RELOAD_URL"] as const;

async function loadConfig(env: Partial<Record<(typeof ENV_KEYS)[number], string>>) {
  vi.resetModules();
  for (const key of ENV_KEYS) delete process.env[key];
  Object.assign(process.env, env);
  const mod = await import("../../capacitor.config");
  return mod.default;
}

afterEach(() => {
  for (const key of ENV_KEYS) delete process.env[key];
});

describe("capacitor.config", () => {
  it("has NO server.url when targeting iOS", async () => {
    const config = await loadConfig({ CAP_TARGET: "ios" });

    expect(config.server?.url).toBeUndefined();
  });

  it("serves iOS from the native bundle directory", async () => {
    const config = await loadConfig({ CAP_TARGET: "ios" });

    expect(config.webDir).toBe("out-native");
  });

  it("allows server.url on iOS only for explicit live reload", async () => {
    const config = await loadConfig({
      CAP_TARGET: "ios",
      CAP_LIVE_RELOAD_URL: "http://192.168.0.10:3000",
    });

    expect(config.server?.url).toBe("http://192.168.0.10:3000");
  });

  it("keeps the Android remote shell exactly as it was", async () => {
    const config = await loadConfig({});

    expect(config.server?.url).toBe("https://easyhealth.art/?native_entry=1");
    expect(config.server?.cleartext).toBe(false);
    expect(config.webDir).toBe("public");
  });

  it("keeps appId stable across targets", async () => {
    const android = await loadConfig({});
    const ios = await loadConfig({ CAP_TARGET: "ios" });

    expect(android.appId).toBe("com.EasyHealth.myapp");
    expect(ios.appId).toBe("com.EasyHealth.myapp");
  });
});

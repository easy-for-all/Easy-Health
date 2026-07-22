import { afterEach, describe, expect, it, vi } from "vitest";
import { api, ApiError } from "@/shared/lib/api";

describe("api error parsing", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("preserves structured billing error fields from nested error payloads", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({
        ok: false,
        status: 503,
        statusText: "Service Unavailable",
        json: async () => ({
          error: {
            code: "billing_configuration_error",
            message: "O pagamento está temporariamente indisponível.",
            request_id: "req_123",
          },
        }),
      })),
    );

    await expect(api.post("/api/v1/billing/checkout", { plan: "pro_yearly" })).rejects.toMatchObject({
      name: "ApiError",
      status: 503,
      errorCode: "billing_configuration_error",
      requestId: "req_123",
      message: "O pagamento está temporariamente indisponível.",
    } satisfies Partial<ApiError>);
  });

  it("keeps compatibility with legacy error payloads", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({
        ok: false,
        status: 422,
        statusText: "Unprocessable Entity",
        json: async () => ({
          error: "invalid_plan",
          message: "Plano inválido",
        }),
      })),
    );

    await expect(api.post("/api/v1/billing/checkout", { plan: "legacy" })).rejects.toMatchObject({
      status: 422,
      errorCode: "invalid_plan",
      message: "Plano inválido",
    } satisfies Partial<ApiError>);
  });
});

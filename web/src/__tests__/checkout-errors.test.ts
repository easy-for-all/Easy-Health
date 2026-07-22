import { beforeEach, describe, expect, it, vi } from "vitest";
import { checkoutErrorMessage, reportCheckoutException } from "@/features/billing/checkout-errors";
import { ApiError } from "@/shared/lib/api";

const { captureExceptionMock, setContextMock, setTagMock, withScopeMock } = vi.hoisted(() => ({
  captureExceptionMock: vi.fn(),
  setContextMock: vi.fn(),
  setTagMock: vi.fn(),
  withScopeMock: vi.fn((callback: (scope: { setTag: (...args: unknown[]) => void; setContext: (...args: unknown[]) => void }) => void) => {
    callback({ setTag: setTagMock, setContext: setContextMock });
  }),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: captureExceptionMock,
  withScope: withScopeMock,
}));

describe("checkoutErrorMessage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("maps auth, invalid plan, and transient billing failures to friendly messages", () => {
    expect(checkoutErrorMessage(new ApiError("unauthorized", 401, "authentication_required"))).toBe(
      "Sua sessão expirou. Entre novamente para continuar.",
    );
    expect(checkoutErrorMessage(new ApiError("bad plan", 422, "billing_invalid_plan"))).toBe(
      "Este plano não está disponível no momento.",
    );
    expect(checkoutErrorMessage(new ApiError("stripe down", 503, "billing_stripe_unavailable"))).toBe(
      "O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.",
    );
    expect(checkoutErrorMessage(new ApiError("proxy", 502, "billing_checkout_creation_failed"))).toBe(
      "O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.",
    );
  });

  it("handles network errors and unexpected errors without leaking internals", () => {
    expect(checkoutErrorMessage(new TypeError("Failed to fetch"))).toBe(
      "Não foi possível conectar ao serviço de pagamento. Tente novamente.",
    );
    expect(checkoutErrorMessage(new Error("raw backend stack"))).toBe(
      "Não foi possível iniciar o checkout. Tente novamente.",
    );
  });

  it("reports checkout failures to Sentry with safe context only", () => {
    reportCheckoutException(
      new ApiError("raw stripe failure with internal details", 502, "billing_checkout_creation_failed", "req_123"),
      { plan: "pro_yearly", source: "billing" },
    );

    expect(setTagMock).toHaveBeenCalledWith("feature", "billing_checkout");
    expect(setTagMock).toHaveBeenCalledWith("checkout_plan", "pro_yearly");
    expect(setTagMock).toHaveBeenCalledWith("checkout_source", "billing");
    expect(setContextMock).toHaveBeenCalledWith("billing_checkout", {
      status: 502,
      error_code: "billing_checkout_creation_failed",
      request_id: "req_123",
    });
    expect(captureExceptionMock).toHaveBeenCalledWith(
      expect.objectContaining({
        message: "O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.",
      }),
    );
  });
});

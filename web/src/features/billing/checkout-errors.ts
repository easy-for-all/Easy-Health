import * as Sentry from "@sentry/nextjs";
import { ApiError } from "@/shared/lib/api";

type CheckoutReportOptions = {
  plan: "pro_monthly" | "pro_yearly";
  source: string;
};

export function checkoutErrorMessage(error: unknown): string {
  if (error instanceof TypeError) {
    return "Não foi possível conectar ao serviço de pagamento. Tente novamente.";
  }

  if (!(error instanceof ApiError)) {
    return "Não foi possível iniciar o checkout. Tente novamente.";
  }

  if (error.status === 401 || error.errorCode === "authentication_required") {
    return "Sua sessão expirou. Entre novamente para continuar.";
  }

  if (error.status === 422 || error.errorCode === "billing_invalid_plan") {
    return "Este plano não está disponível no momento.";
  }

  if (
    error.status === 502 ||
    error.status === 503 ||
    error.errorCode === "billing_configuration_error" ||
    error.errorCode === "billing_stripe_unavailable" ||
    error.errorCode === "billing_checkout_creation_failed" ||
    error.errorCode === "billing_customer_error"
  ) {
    return "O pagamento está temporariamente indisponível. Tente novamente em alguns minutos.";
  }

  return "Não foi possível iniciar o checkout. Tente novamente.";
}

export function checkoutErrorCode(error: unknown): string {
  if (error instanceof ApiError) return error.errorCode ?? String(error.status);
  if (error instanceof TypeError) return "network_error";
  return "checkout_error";
}

export function reportCheckoutException(error: unknown, options: CheckoutReportOptions): void {
  const safeError = new Error(checkoutErrorMessage(error));
  safeError.name = error instanceof Error ? error.name : "CheckoutError";

  Sentry.withScope((scope) => {
    scope.setTag("feature", "billing_checkout");
    scope.setTag("checkout_plan", options.plan);
    scope.setTag("checkout_source", options.source);

    if (error instanceof ApiError) {
      scope.setContext("billing_checkout", {
        status: error.status,
        error_code: error.errorCode,
        request_id: error.requestId,
      });
    }

    Sentry.captureException(safeError);
  });
}

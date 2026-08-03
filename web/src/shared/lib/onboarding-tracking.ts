import { api } from "@/shared/lib/api";

export type OnboardingFlow = "quick" | "complete" | "photo_ai" | "chat_ai";

interface TrackOnboardingEventOptions {
  onboardingFlow?: OnboardingFlow;
  stepName?: string;
  metadata?: Record<string, unknown>;
}

// POST /api/v1/onboarding_events é escopado em current_user e responde 401 sem
// sessão. Desde que o onboarding pode acontecer ANTES da conta existir, chamar
// esse endpoint na etapa pré-auth só produziria uma fila de 401 barulhentos.
//
// O indicador é o cookie não-httponly que a API grava junto com a sessão e o
// AuthProvider apaga no 401 — o mesmo sinal que o proxy usa na borda. Errar para
// "não autenticado" só custa um evento desta trilha; o funil pré-auth de verdade
// vive no pipeline de product-analytics, que aceita anônimo.
function hasSession(): boolean {
  if (typeof document === "undefined") return false;
  return document.cookie.split("; ").some((entry) => entry.startsWith("_eh_auth="));
}

export function trackOnboardingEvent(eventName: string, options: TrackOnboardingEventOptions = {}): void {
  if (!hasSession()) return;

  api
    .post("/api/v1/onboarding_events", {
      event_name: eventName,
      onboarding_flow: options.onboardingFlow,
      step_name: options.stepName,
      metadata: options.metadata ?? {},
    })
    .catch((err) => {
      console.error("[OnboardingTracking]", eventName, err);
    });
}

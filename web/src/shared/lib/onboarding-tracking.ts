import { api } from "@/shared/lib/api";

export type OnboardingFlow = "quick" | "complete" | "photo_ai" | "chat_ai";

interface TrackOnboardingEventOptions {
  onboardingFlow?: OnboardingFlow;
  stepName?: string;
  metadata?: Record<string, unknown>;
}

export function trackOnboardingEvent(eventName: string, options: TrackOnboardingEventOptions = {}): void {
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

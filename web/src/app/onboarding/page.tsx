"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { PlanCreationFlow } from "@/features/plan-creation/plan-creation-flow";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { trackOnboardingEvent } from "@/shared/lib/onboarding-tracking";
import { useIsHydrated } from "@/shared/lib/platform";

export default function OnboardingPage() {
  const router = useRouter();
  // O wizard retoma o rascunho local já na inicialização do estado, e localStorage
  // não existe no servidor. Montá-lo só depois da hidratação faz o primeiro render
  // dele acontecer uma vez só, no cliente, em vez de divergir do HTML prerenderizado.
  const hydrated = useIsHydrated();

  useEffect(() => {
    trackEvent(EVENTS.ONBOARDING_STARTED);
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "onboarding" });
    trackOnboardingEvent("onboarding_started", { stepName: "choose_flow" });
  }, []);

  if (!hydrated) return null;

  return (
    <PlanCreationFlow
      entryMode="onboarding"
      initialProfile={null}
      onDone={(_plan, mode) => {
        trackEvent(EVENTS.ONBOARDING_COMPLETED);
        trackOnboardingEvent("onboarding_completed", { onboardingFlow: mode });
        router.push("/workouts/ready");
      }}
    />
  );
}

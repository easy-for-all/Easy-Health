"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { PlanCreationFlow } from "@/features/plan-creation/plan-creation-flow";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { trackOnboardingEvent } from "@/shared/lib/onboarding-tracking";

export default function OnboardingPage() {
  const router = useRouter();

  useEffect(() => {
    trackEvent(EVENTS.ONBOARDING_STARTED);
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "onboarding" });
    trackOnboardingEvent("onboarding_started", { stepName: "choose_flow" });
  }, []);

  return (
    <PlanCreationFlow
      entryMode="onboarding"
      initialProfile={null}
      onDone={(_plan, mode) => {
        trackEvent(EVENTS.ONBOARDING_COMPLETED);
        trackOnboardingEvent("onboarding_completed", { onboardingFlow: mode });
        router.push("/workouts");
      }}
    />
  );
}

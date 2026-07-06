"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { PlanCreationFlow } from "@/features/plan-creation/plan-creation-flow";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";

export default function OnboardingPage() {
  const router = useRouter();

  useEffect(() => {
    trackEvent(EVENTS.ONBOARDING_STARTED);
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "onboarding" });
  }, []);

  return (
    <PlanCreationFlow
      entryMode="onboarding"
      initialProfile={null}
      onDone={() => {
        trackEvent(EVENTS.ONBOARDING_COMPLETED);
        router.push("/workouts");
      }}
    />
  );
}

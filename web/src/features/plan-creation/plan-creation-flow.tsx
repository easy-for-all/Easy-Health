"use client";

import type { HealthProfile } from "@/shared/types/health-profile";
import type { WorkoutPlan } from "@/shared/types/workout";
import "@/shared/components/ui/ui.css";
import { usePlanCreationWizard } from "./use-plan-creation-wizard";
import { ErrorStep, GeneratingStep } from "./shared-steps";
import { CreateStart } from "./screens/create-start";
import { QuickGoal } from "./screens/quick/quick-goal";
import { QuickProfile } from "./screens/quick/quick-profile";
import { QuickPlace } from "./screens/quick/quick-place";
import { QuickTime } from "./screens/quick/quick-time";
import { QuickLimits } from "./screens/quick/quick-limits";
import { CompleteMethod } from "./screens/complete/complete-method";
import { CompletePlace } from "./screens/complete/complete-place";
import { CompleteFocus } from "./screens/complete/complete-focus";
import { CompleteSchedule } from "./screens/complete/complete-schedule";
import { CompleteCare } from "./screens/complete/complete-care";
import type { CreationMode, EntryMode } from "./types";

export function PlanCreationFlow({
  entryMode, initialProfile, onDone, onCancel,
}: {
  entryMode: EntryMode;
  initialProfile: HealthProfile | null;
  onDone: (plan: WorkoutPlan, mode: CreationMode) => void;
  onCancel?: () => void;
}) {
  const wizard = usePlanCreationWizard(entryMode, initialProfile);

  async function handleFinish() {
    const plan = await wizard.runGeneration();
    if (plan) onDone(plan, wizard.mode);
  }

  async function handleRetry() {
    const plan = await wizard.retry();
    if (plan) onDone(plan, wizard.mode);
  }

  if (wizard.phase === "generating") {
    return <GeneratingStep modality={wizard.form.modality} />;
  }

  if (wizard.phase === "error") {
    return <ErrorStep error={wizard.error} onRetry={handleRetry} onBack={wizard.goBack} />;
  }

  return (
    <div className="wizard-screen">
      {wizard.phase === "start" && <CreateStart onSelect={wizard.start} onCancel={onCancel} />}

      {wizard.phase === "form" && wizard.stepId === "quick-goal" && <QuickGoal wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "quick-profile" && <QuickProfile wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "quick-place" && <QuickPlace wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "quick-time" && <QuickTime wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "quick-limits" && <QuickLimits wizard={wizard} onFinish={handleFinish} />}

      {wizard.phase === "form" && wizard.stepId === "complete-goal" && <QuickGoal wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-profile" && <QuickProfile wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-method" && <CompleteMethod wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-place" && <CompletePlace wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-focus" && <CompleteFocus wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-schedule" && <CompleteSchedule wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-care" && <CompleteCare wizard={wizard} onFinish={handleFinish} />}
    </div>
  );
}

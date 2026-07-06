"use client";

import { useMemo, useRef, useState } from "react";
import { ApiError } from "@/shared/lib/api";
import { EVENTS, trackEvent } from "@/shared/lib/analytics";
import type { HealthProfile } from "@/shared/types/health-profile";
import type { WorkoutPlan } from "@/shared/types/workout";
import { stepsForMode } from "./flows";
import { generatePlan, upsertProfile } from "./submit";
import { hydrateFormFromProfile, type CreationMode, type EntryMode, type StepId, type WizardFormState } from "./types";

type Phase = "start" | "form" | "generating" | "error";

export function usePlanCreationWizard(entryMode: EntryMode, initialProfile: HealthProfile | null) {
  const hasExistingProfile = !!initialProfile;
  const [mode, setMode] = useState<CreationMode>("quick");
  const [phase, setPhase] = useState<Phase>("start");
  const [stepId, setStepId] = useState<StepId>("create-start");
  const [form, setForm] = useState<WizardFormState>(() => hydrateFormFromProfile(initialProfile));
  const [error, setError] = useState("");
  const lastFormRef = useRef<WizardFormState | null>(null);

  const steps = useMemo(() => stepsForMode(mode, { hasExistingProfile }), [mode, hasExistingProfile]);
  const stepIndex = steps.indexOf(stepId);
  const progress = { current: Math.max(stepIndex, 0), total: steps.length };

  function set<K extends keyof WizardFormState>(key: K, value: WizardFormState[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function start(selected: CreationMode) {
    setMode(selected);
    setStepId(stepsForMode(selected, { hasExistingProfile })[0]);
    setError("");
    setPhase("form");
  }

  function goNext() {
    const idx = steps.indexOf(stepId);
    if (idx === -1 || idx >= steps.length - 1) return;
    setStepId(steps[idx + 1]);
  }

  function goBack() {
    const idx = steps.indexOf(stepId);
    if (idx <= 0) {
      setPhase("start");
      setStepId("create-start");
      return;
    }
    setStepId(steps[idx - 1]);
  }

  async function runGeneration(): Promise<WorkoutPlan | null> {
    setPhase("generating");
    setError("");
    lastFormRef.current = form;
    try {
      await upsertProfile(entryMode, form);
      const plan = await generatePlan(form);
      trackEvent(EVENTS.WORKOUT_CREATED, { workout_days: plan.days.length, modality: form.modality });
      trackEvent(EVENTS.AI_WORKOUT_GENERATED, { modality: form.modality });
      return plan;
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        window.location.replace("/login");
        return null;
      }
      setError(err instanceof Error ? err.message : "Erro ao gerar planejamento. Tente novamente.");
      setPhase("error");
      return null;
    }
  }

  function retry(): Promise<WorkoutPlan | null> {
    if (lastFormRef.current) setForm(lastFormRef.current);
    return runGeneration();
  }

  return {
    mode, phase, stepId, form, error, steps, progress,
    set, start, goNext, goBack, runGeneration, retry,
  };
}

export type PlanCreationWizard = ReturnType<typeof usePlanCreationWizard>;

"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { ApiError } from "@/shared/lib/api";
import { AnonApiError } from "@/features/anonymous/anon-api";
import { EVENTS, trackEvent } from "@/shared/lib/analytics";
import { trackOnboardingEvent } from "@/shared/lib/onboarding-tracking";
import type { HealthProfile } from "@/shared/types/health-profile";
import type { WorkoutPlan } from "@/shared/types/workout";
import { clearDraft, loadDraft, saveDraft } from "./draft";
import { stepsForMode } from "./flows";
import { generatePlan, upsertProfile, type SubmitMode } from "./submit";
import { hydrateFormFromProfile, type CreationMode, type EntryMode, type StepId, type WizardFormState } from "./types";

type Phase = "start" | "form" | "generating" | "error";

// Campos do formulário coletados em cada etapa, usados apenas para enriquecer o
// evento de analytics onboarding_step_completed (não afeta a navegação do wizard).
const STEP_FIELDS: Partial<Record<StepId, (keyof WizardFormState)[]>> = {
  "quick-goal": ["goal"],
  "quick-profile": ["age", "fitness_level", "gender", "height_cm", "weight_kg"],
  "quick-place": ["training_location"],
  "quick-time": ["session_duration_minutes", "training_days_per_week"],
  "quick-when": ["preferred_workout_period", "preferred_workout_time"],
  "quick-limits": ["limitations"],
  "complete-goal": ["goal"],
  "complete-profile": ["age", "fitness_level", "gender", "height_cm", "weight_kg"],
  "complete-method": ["modality", "split_type", "cardio_type", "cardio_format"],
  "complete-place": ["training_location", "available_equipment"],
  "complete-focus": ["preferred_body_focus", "preferred_training_styles", "selected_muscles", "muscle_priorities"],
  "complete-schedule": ["session_duration_minutes", "training_days_per_week", "intensity_preference", "limitations"],
  "complete-when": ["preferred_workout_period", "preferred_workout_time"],
  "complete-care": ["favorite_exercises", "avoided_exercises"],
};

function stepFieldsSnapshot(stepId: StepId, form: WizardFormState): Record<string, unknown> {
  const fields = STEP_FIELDS[stepId] ?? [];
  return Object.fromEntries(fields.map((key) => [key, form[key]]));
}

export interface WizardOptions {
  // Acrescenta a etapa de resumo ao final do fluxo. Quem liga isto é responsável
  // por decidir o que acontece no fim — ver onRequireAuth em PlanCreationFlow.
  withPreview?: boolean;
  // Para onde a geração vai. O wizard continua ignorante sobre autenticação:
  // ele não decide se há conta, só repassa o que a página decidiu.
  submitMode?: SubmitMode;
}

export function usePlanCreationWizard(
  entryMode: EntryMode,
  initialProfile: HealthProfile | null,
  { withPreview = false, submitMode = "authenticated" }: WizardOptions = {},
) {
  const hasExistingProfile = !!initialProfile;

  // O rascunho é do onboarding, não do replan: quem já tem plano abre o wizard
  // para mudar algo específico e seria surpreendido por respostas de uma sessão
  // antiga. hydrateFormFromProfile já cobre o replan a partir do backend.
  const persists = entryMode === "onboarding";

  // Lido uma única vez, na inicialização do estado, e não num efeito: retomar via
  // setState depois da montagem custa um render em cascata e faz a tela piscar na
  // etapa "escolha o modo" antes de saltar para onde a pessoa estava. Quem monta
  // este hook com entryMode "onboarding" precisa garantir que o primeiro render
  // aconteça só depois da hidratação — ver o portão em app/onboarding/page.tsx —,
  // porque o servidor não tem localStorage e os dois renders divergiriam.
  const [resumed] = useState(() => (persists ? loadDraft() : null));

  const [mode, setMode] = useState<CreationMode>(resumed?.mode ?? "quick");
  const [phase, setPhase] = useState<Phase>(resumed ? "form" : "start");
  const [stepId, setStepId] = useState<StepId>(resumed?.stepId ?? "create-start");
  const [form, setForm] = useState<WizardFormState>(() => resumed?.form ?? hydrateFormFromProfile(initialProfile));
  const [error, setError] = useState("");
  const lastFormRef = useRef<WizardFormState | null>(null);

  const steps = useMemo(
    () => stepsForMode(mode, { hasExistingProfile, withPreview }),
    [mode, hasExistingProfile, withPreview],
  );
  const stepIndex = steps.indexOf(stepId);
  const progress = { current: Math.max(stepIndex, 0), total: steps.length };
  // Quem chama onFinish está dizendo "terminei minha etapa", não "gere o plano":
  // com o resumo ativo ainda há uma tela pela frente.
  const isLastStep = stepIndex === steps.length - 1;

  useEffect(() => {
    if (phase !== "form") return;
    trackOnboardingEvent("onboarding_step_viewed", { onboardingFlow: mode, stepName: stepId });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, stepId]);

  // Persistência a partir do estado já commitado, e não de dentro de goNext: as
  // telas de toque único fazem set(...) e goNext() no mesmo handler, então o
  // `form` visível dentro de goNext ainda é o anterior e gravaria a resposta que
  // o usuário acabou de dar como vazia.
  useEffect(() => {
    if (!persists || phase !== "form") return;
    saveDraft({ mode, stepId, form });
  }, [persists, phase, mode, stepId, form]);

  function set<K extends keyof WizardFormState>(key: K, value: WizardFormState[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function start(selected: CreationMode) {
    setMode(selected);
    setStepId(stepsForMode(selected, { hasExistingProfile, withPreview })[0]);
    setError("");
    setPhase("form");
  }

  function goNext() {
    const idx = steps.indexOf(stepId);
    if (idx === -1 || idx >= steps.length - 1) return;
    trackOnboardingEvent("onboarding_step_completed", {
      onboardingFlow: mode,
      stepName: stepId,
      metadata: stepFieldsSnapshot(stepId, form),
    });
    setStepId(steps[idx + 1]);
  }

  function goBack() {
    const idx = steps.indexOf(stepId);
    if (idx <= 0) {
      // Voltar para a escolha de modo desfaz o fluxo: manter o rascunho aqui
      // faria um reload retomar num formulário que o usuário acabou de abandonar.
      if (persists) clearDraft();
      setPhase("start");
      setStepId("create-start");
      return;
    }
    setStepId(steps[idx - 1]);
  }

  async function runGeneration(): Promise<WorkoutPlan | null> {
    trackOnboardingEvent("onboarding_step_completed", {
      onboardingFlow: mode,
      stepName: stepId,
      metadata: stepFieldsSnapshot(stepId, form),
    });
    trackOnboardingEvent("plan_generation_started", { onboardingFlow: mode });
    const startedAt = Date.now();

    setPhase("generating");
    setError("");
    lastFormRef.current = form;
    try {
      await upsertProfile(entryMode, form, submitMode);
      const plan = await generatePlan(form, submitMode);
      trackEvent(EVENTS.WORKOUT_CREATED, { workout_days: plan.days.length, modality: form.modality });
      trackEvent(EVENTS.AI_WORKOUT_GENERATED, { modality: form.modality });
      trackOnboardingEvent("plan_created", {
        onboardingFlow: mode,
        metadata: { generated_plan_id: plan.id, duration_seconds: Math.round((Date.now() - startedAt) / 1000) },
      });
      // Só aqui: enquanto a geração puder ser repetida (phase "error" com retry),
      // as respostas precisam continuar no dispositivo.
      if (persists) clearDraft();
      return plan;
    } catch (err) {
      // O 4º plano sem conta. Não é erro que se resolve tentando de novo: é a
      // fronteira do que o produto entrega de graça, e a única saída é criar a
      // conta. Deixar isso cair na tela de erro genérica ofereceria um botão
      // "Tentar novamente" que o servidor vai recusar de novo, para sempre.
      if (err instanceof AnonApiError && err.isLimitReached) {
        trackEvent("anonymous_plan_limit_reached", { onboarding_flow: mode });
        window.location.replace("/sign-up?from=anonymous_limit");
        return null;
      }
      // No fluxo autenticado um 401 é sessão expirada. No anônimo é o token que
      // venceu — e mandar para /login ali descartaria um plano que a pessoa
      // acabou de pedir, num fluxo onde ela nem tem conta para entrar.
      if (submitMode === "authenticated" && err instanceof ApiError && err.status === 401) {
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
    mode, phase, stepId, form, error, steps, progress, isLastStep,
    set, start, goNext, goBack, runGeneration, retry,
  };
}

export type PlanCreationWizard = ReturnType<typeof usePlanCreationWizard>;

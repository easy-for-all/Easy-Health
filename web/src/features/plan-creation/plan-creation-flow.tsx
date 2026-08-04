"use client";

import { useEffect, useRef } from "react";
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
import { WhenStep } from "./screens/shared/when-step";
import { PlanPreview } from "./screens/plan-preview";
import type { CreationMode, EntryMode } from "./types";

export function PlanCreationFlow({
  entryMode, initialProfile, onDone, onCancel, onRequireAuth, autoGenerate, withPreview, onBeforeFinish,
}: {
  entryMode: EntryMode;
  initialProfile: HealthProfile | null;
  onDone: (plan: WorkoutPlan, mode: CreationMode) => void;
  onCancel?: () => void;
  // Presente apenas quando o onboarding roda antes de a conta existir. Quem
  // decide isso é a página, que é quem conhece a sessão — o wizard permanece
  // ignorante sobre autenticação.
  onRequireAuth?: () => void;
  // Volta do cadastro com o wizard já preenchido pelo rascunho. A pessoa tocou
  // "Ver meu treino" antes de criar a conta; obrigá-la a tocar de novo no mesmo
  // botão trata o cadastro como se tivesse cancelado o pedido.
  autoGenerate?: boolean;
  // A tela de resumo era acoplada a onRequireAuth porque as duas descreviam o
  // mesmo fluxo. Deixaram de descrever: no fim do onboarding pré-auth o resumo
  // aparece nas duas variantes do experimento, e só uma delas pede a conta.
  // Continua caindo no comportamento antigo quando não é informado.
  withPreview?: boolean;
  // Chamado no fim do wizard, ANTES de decidir para onde ir. É onde a página
  // registra que a bifurcação aconteceu de fato — o componente segue ignorante
  // sobre experimento, do mesmo jeito que é sobre autenticação.
  onBeforeFinish?: (mode: CreationMode) => void;
}) {
  const wizard = usePlanCreationWizard(entryMode, initialProfile, {
    withPreview: withPreview ?? !!onRequireAuth,
  });

  async function handleFinish() {
    // A última tela de conteúdo diz "terminei", não "gere agora": com o resumo
    // ativo ainda falta uma etapa antes de qualquer chamada à API.
    if (!wizard.isLastStep) {
      wizard.goNext();
      return;
    }
    onBeforeFinish?.(wizard.mode);
    if (onRequireAuth) {
      onRequireAuth();
      return;
    }
    const plan = await wizard.runGeneration();
    if (plan) onDone(plan, wizard.mode);
  }

  async function handleRetry() {
    const plan = await wizard.retry();
    if (plan) onDone(plan, wizard.mode);
  }

  // Gera direto, sem passar pela máquina de passos: o rascunho retomado já traz o
  // formulário inteiro, e a posição salva nele descreve um fluxo que tinha a tela
  // de resumo — que não existe mais agora que a conta existe. Perguntar "qual é a
  // última etapa?" aqui responderia sobre o fluxo errado.
  const autoStartedRef = useRef(false);
  useEffect(() => {
    if (!autoGenerate || autoStartedRef.current) return;
    autoStartedRef.current = true;
    void (async () => {
      const plan = await wizard.runGeneration();
      if (plan) onDone(plan, wizard.mode);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoGenerate]);

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
      {wizard.phase === "form" && wizard.stepId === "quick-when" && <WhenStep wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "quick-limits" && <QuickLimits wizard={wizard} onFinish={handleFinish} />}

      {wizard.phase === "form" && wizard.stepId === "complete-goal" && <QuickGoal wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-profile" && <QuickProfile wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-method" && <CompleteMethod wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-place" && <CompletePlace wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-focus" && <CompleteFocus wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-schedule" && <CompleteSchedule wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-when" && <WhenStep wizard={wizard} />}
      {wizard.phase === "form" && wizard.stepId === "complete-care" && <CompleteCare wizard={wizard} onFinish={handleFinish} />}

      {wizard.phase === "form" && wizard.stepId === "plan-preview" && <PlanPreview wizard={wizard} onFinish={handleFinish} />}
    </div>
  );
}

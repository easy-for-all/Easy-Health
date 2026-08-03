"use client";

import { useEffect } from "react";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import { trackEvent } from "@/shared/lib/analytics";
import { GOALS, LOCATIONS } from "./options";
import type { PlanCreationWizard } from "../use-plan-creation-wizard";
import type { Modality, WizardFormState } from "../types";

const MODALITY_LABELS: Record<Modality, string> = {
  musculacao: "Musculação",
  cardio: "Cardio",
  misto: "Musculação + cardio",
  funcional: "Funcional",
  ai_choice: "Formato escolhido pela IA",
};

// Derivado só do que a pessoa respondeu. Nenhuma chamada de API acontece aqui:
// a geração do plano é síncrona, leva até 90s e pode falhar, então prometer um
// treino pronto ANTES da conta existir seria uma promessa que a tela seguinte
// não consegue cumprir. O que se promete aqui é o que já é verdade — sabemos o
// bastante para montar o plano.
export function summarize(form: WizardFormState): { label: string; value: string }[] {
  const goal = GOALS.find((option) => option.value === form.goal);
  const location = LOCATIONS.find((option) => option.value === form.training_location);

  const rows: { label: string; value: string }[] = [];
  if (goal) rows.push({ label: "Objetivo", value: goal.label });
  rows.push({ label: "Formato", value: MODALITY_LABELS[form.modality] });
  if (form.training_days_per_week) {
    rows.push({ label: "Frequência", value: `${form.training_days_per_week}x por semana` });
  }
  if (form.session_duration_minutes) {
    rows.push({ label: "Duração", value: `${form.session_duration_minutes} min por treino` });
  }
  if (location) rows.push({ label: "Onde", value: location.label });
  if (form.limitations.length > 0) {
    rows.push({ label: "Respeitando", value: form.limitations.join(", ") });
  }
  return rows;
}

export function PlanPreview({ wizard, onFinish }: { wizard: PlanCreationWizard; onFinish: () => void }) {
  const rows = summarize(wizard.form);

  useEffect(() => {
    trackEvent("plan_preview_viewed", {
      onboarding_flow: wizard.mode,
      goal: wizard.form.goal || undefined,
      modality: wizard.form.modality,
      training_days_per_week: wizard.form.training_days_per_week ?? undefined,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Já temos o seu plano</h2>
      <p className="wizard-sub">Crie sua conta para ver os exercícios, dia a dia.</p>

      <dl className="preview-card">
        {rows.map((row) => (
          <div key={row.label} className="preview-row">
            <dt>{row.label}</dt>
            <dd>{row.value}</dd>
          </div>
        ))}
      </dl>

      <button className="wizard-cta" onClick={onFinish}>Ver meu treino</button>
      <p className="preview-note">7 dias grátis · Sem cartão</p>
    </div>
  );
}

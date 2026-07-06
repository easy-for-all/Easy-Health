"use client";

import { ChoiceGrid } from "@/shared/components/ui/choice-grid";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import { SliderRow } from "@/shared/components/ui/slider-row";
import type { Duration } from "../../types";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

// session_duration_minutes valida contra um enum fixo no backend (15/25/35/45/60) — por isso é
// uma grade de opções, não um slider contínuo como no protótipo visual.
const DURATIONS: { value: string; label: string }[] = [15, 25, 35, 45, 60].map((value) => ({
  value: String(value),
  label: value === 60 ? "60 min ou mais" : `${value} min`,
}));

export function QuickTime({ wizard }: { wizard: PlanCreationWizard }) {
  const { form, set } = wizard;

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Tempo por treino e frequência</h2>
      <p className="wizard-sub">Ajustamos o plano para caber na sua rotina.</p>

      <p className="wizard-sub" style={{ marginBottom: 8 }}>Tempo por treino</p>
      <ChoiceGrid
        values={DURATIONS}
        selected={form.session_duration_minutes ? [String(form.session_duration_minutes)] : []}
        onToggle={(value) => set("session_duration_minutes", Number(value) as Duration)}
      />

      <div style={{ marginTop: 20 }}>
        <SliderRow
          label="Vezes por semana"
          value={form.training_days_per_week ?? 3}
          min={1}
          max={6}
          onChange={(value) => set("training_days_per_week", value)}
        />
      </div>

      <button className="wizard-cta" disabled={!form.session_duration_minutes} onClick={wizard.goNext}>Continuar →</button>
    </div>
  );
}

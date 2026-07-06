"use client";

import { ChoiceGrid } from "@/shared/components/ui/choice-grid";
import { OptionCard } from "@/shared/components/ui/option-card";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import { BODY_FOCUS, TRAINING_STYLES } from "../options";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

export function CompleteFocus({ wizard }: { wizard: PlanCreationWizard }) {
  const { form, set } = wizard;

  function toggleFocus(value: (typeof BODY_FOCUS)[number]["value"]) {
    const active = form.preferred_body_focus.includes(value);
    if (active) { set("preferred_body_focus", form.preferred_body_focus.filter((item) => item !== value)); return; }
    if (form.preferred_body_focus.length >= 3) return;
    set("preferred_body_focus", [...form.preferred_body_focus, value]);
  }

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Focos e preferências</h2>
      <p className="wizard-sub">Escolha até três focos musculares para priorizar.</p>
      <ChoiceGrid values={BODY_FOCUS} selected={form.preferred_body_focus} limit={3} onToggle={toggleFocus} />

      <p className="wizard-sub" style={{ marginTop: 20 }}>Qual estilo de treino você prefere?</p>
      <div className="opts">
        {TRAINING_STYLES.map((style) => (
          <OptionCard
            key={style.value}
            icon="✦"
            label={style.label}
            selected={form.preferred_training_styles[0] === style.value}
            onClick={() => set("preferred_training_styles", [style.value])}
          />
        ))}
      </div>

      <button className="wizard-cta" onClick={wizard.goNext}>Continuar →</button>
      <button className="wizard-back" onClick={wizard.goNext}>Pular agora</button>
    </div>
  );
}

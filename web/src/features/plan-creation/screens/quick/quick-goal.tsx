"use client";

import { OptionCard } from "@/shared/components/ui/option-card";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import { GOALS } from "../options";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

export function QuickGoal({ wizard }: { wizard: PlanCreationWizard }) {
  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Qual é o seu objetivo?</h2>
      <p className="wizard-sub">A IA monta a estratégia toda em volta disso.</p>
      <div className="opts">
        {GOALS.map((goal) => (
          <OptionCard
            key={goal.value}
            icon={goal.icon}
            label={goal.label}
            description={goal.desc}
            selected={wizard.form.goal === goal.value}
            onClick={() => { wizard.set("goal", goal.value); wizard.goNext(); }}
          />
        ))}
      </div>
    </div>
  );
}

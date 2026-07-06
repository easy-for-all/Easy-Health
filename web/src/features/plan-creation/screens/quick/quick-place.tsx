"use client";

import { OptionCard } from "@/shared/components/ui/option-card";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import { LOCATIONS } from "../options";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

export function QuickPlace({ wizard }: { wizard: PlanCreationWizard }) {
  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Onde você treina?</h2>
      <p className="wizard-sub">Assim respeitamos sua realidade, sem adivinhação.</p>
      <div className="opts">
        {LOCATIONS.map((location) => (
          <OptionCard
            key={location.value}
            icon={location.icon}
            label={location.label}
            description={location.desc}
            selected={wizard.form.training_location === location.value}
            onClick={() => { wizard.set("training_location", location.value); wizard.goNext(); }}
          />
        ))}
      </div>
    </div>
  );
}

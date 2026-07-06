"use client";

import { useState } from "react";
import { ChoiceGrid } from "@/shared/components/ui/choice-grid";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import { SegmentedControl } from "@/shared/components/ui/segmented-control";
import { LIMITATION_PRESETS } from "../options";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

export function QuickLimits({ wizard, onFinish }: { wizard: PlanCreationWizard; onFinish: () => void }) {
  const { form, set } = wizard;
  const [hasLimitation, setHasLimitation] = useState(form.limitations.length > 0);

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Tem alguma limitação importante?</h2>
      <p className="wizard-sub">Ajustamos os exercícios para respeitar isso.</p>

      <SegmentedControl
        options={[{ value: "no" as const, label: "Não" }, { value: "yes" as const, label: "Sim" }]}
        value={hasLimitation ? "yes" : "no"}
        onChange={(value) => {
          const yes = value === "yes";
          setHasLimitation(yes);
          if (!yes) set("limitations", []);
        }}
      />

      {hasLimitation && (
        <div style={{ marginTop: 16 }}>
          <ChoiceGrid
            values={LIMITATION_PRESETS.map((value) => ({ value, label: value }))}
            selected={form.limitations}
            onToggle={(value) => {
              const active = form.limitations.includes(value);
              set("limitations", active ? form.limitations.filter((item) => item !== value) : [...form.limitations, value]);
            }}
          />
        </div>
      )}

      <button className="wizard-cta" onClick={onFinish}>Criar treino ✨</button>
    </div>
  );
}

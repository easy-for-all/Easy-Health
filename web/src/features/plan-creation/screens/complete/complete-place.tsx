"use client";

import { ChoiceGrid } from "@/shared/components/ui/choice-grid";
import { OptionCard } from "@/shared/components/ui/option-card";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import type { Equipment } from "@/shared/types/health-profile";
import { EQUIPMENT, LOCATIONS } from "../options";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

export function CompletePlace({ wizard }: { wizard: PlanCreationWizard }) {
  const { form, set } = wizard;

  function toggleEquipment(value: Equipment) {
    const active = form.available_equipment.includes(value);
    if (!active && value === "none") { set("available_equipment", ["none"]); return; }
    const next = value === "none" ? [] : form.available_equipment.filter((item) => item !== "none");
    set("available_equipment", active ? next.filter((item) => item !== value) : [...next, value]);
  }

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Onde você vai treinar?</h2>
      <p className="wizard-sub">Isso adapta os exercícios e equipamentos do seu plano.</p>

      <div className="opts">
        {LOCATIONS.map((location) => (
          <OptionCard
            key={location.value}
            icon={location.icon}
            label={location.label}
            description={location.desc}
            selected={form.training_location === location.value}
            onClick={() => set("training_location", location.value)}
          />
        ))}
      </div>

      <p className="wizard-sub" style={{ marginTop: 20, marginBottom: 8 }}>Equipamentos disponíveis</p>
      <ChoiceGrid values={EQUIPMENT} selected={form.available_equipment} onToggle={toggleEquipment} />

      <button className="wizard-cta" disabled={!form.training_location} onClick={wizard.goNext}>Continuar →</button>
    </div>
  );
}

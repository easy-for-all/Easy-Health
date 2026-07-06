"use client";

import { OptionCard } from "@/shared/components/ui/option-card";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import { SegmentedControl } from "@/shared/components/ui/segmented-control";
import { SliderRow } from "@/shared/components/ui/slider-row";
import { LEVELS } from "../options";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

const GENDER_OPTIONS = [
  { value: "male" as const, label: "Homem" },
  { value: "female" as const, label: "Mulher" },
  { value: "not_informed" as const, label: "Prefiro não informar" },
];

export function QuickProfile({ wizard }: { wizard: PlanCreationWizard }) {
  const { form, set } = wizard;

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Seu nível e seus dados físicos</h2>
      <p className="wizard-sub">Usamos isso para ajustar a intensidade com segurança.</p>

      <div className="opts">
        {LEVELS.map((level) => (
          <OptionCard
            key={level.value}
            icon={level.icon}
            label={level.label}
            description={level.desc}
            selected={form.fitness_level === level.value}
            onClick={() => set("fitness_level", level.value)}
          />
        ))}
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 14, marginTop: 20 }}>
        <SegmentedControl options={GENDER_OPTIONS} value={form.gender || "male"} onChange={(value) => set("gender", value)} />
        <SliderRow label="Idade" unit=" anos" value={Number(form.age)} min={14} max={90} onChange={(value) => set("age", String(value))} />
        <SliderRow label="Peso" unit="kg" value={Number(form.weight_kg)} min={35} max={180} onChange={(value) => set("weight_kg", String(value))} />
        <SliderRow label="Altura" unit="cm" value={Number(form.height_cm)} min={120} max={220} onChange={(value) => set("height_cm", String(value))} />
      </div>

      <button className="wizard-cta" disabled={!form.fitness_level} onClick={wizard.goNext}>Continuar →</button>
    </div>
  );
}

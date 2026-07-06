"use client";

import { useState } from "react";
import { ChoiceGrid } from "@/shared/components/ui/choice-grid";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import { SegmentedControl } from "@/shared/components/ui/segmented-control";
import { SliderRow } from "@/shared/components/ui/slider-row";
import { INTENSITIES } from "../options";
import type { Duration } from "../../types";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

const DURATIONS: { value: string; label: string }[] = [15, 25, 35, 45, 60].map((value) => ({
  value: String(value),
  label: value === 60 ? "60 min ou mais" : `${value} min`,
}));

export function CompleteSchedule({ wizard }: { wizard: PlanCreationWizard }) {
  const { form, set } = wizard;
  const [hasRestriction, setHasRestriction] = useState(form.limitations.length > 0);

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Tempo e frequência</h2>
      <p className="wizard-sub">Tudo aqui é ajustável depois.</p>

      <SliderRow
        label="Dias por semana"
        value={form.training_days_per_week ?? 4}
        min={2}
        max={6}
        onChange={(value) => set("training_days_per_week", value)}
      />

      <p className="wizard-sub" style={{ marginTop: 12, marginBottom: 8 }}>Tempo por treino</p>
      <ChoiceGrid
        values={DURATIONS}
        selected={form.session_duration_minutes ? [String(form.session_duration_minutes)] : []}
        onToggle={(value) => set("session_duration_minutes", Number(value) as Duration)}
      />

      <p className="wizard-sub" style={{ marginTop: 18, marginBottom: 8 }}>Intensidade desejada</p>
      <SegmentedControl
        options={INTENSITIES.slice(0, 3)}
        value={form.intensity_preference || "balanced"}
        onChange={(value) => set("intensity_preference", value)}
      />

      <p className="wizard-sub" style={{ marginTop: 18, marginBottom: 8 }}>Restrição ou lesão</p>
      <SegmentedControl
        options={[{ value: "none" as const, label: "Nenhuma" }, { value: "has" as const, label: "Tenho uma restrição" }]}
        value={hasRestriction ? "has" : "none"}
        onChange={(value) => {
          const has = value === "has";
          setHasRestriction(has);
          if (!has) set("limitations", []);
        }}
      />
      {hasRestriction && (
        <input
          value={form.limitations[0] ?? ""}
          onChange={(event) => set("limitations", event.target.value ? [event.target.value] : [])}
          placeholder="Descreva rapidamente"
          style={{ marginTop: 10, width: "100%", borderRadius: "var(--r-sm)", border: "1.5px solid var(--border)", background: "var(--bg-2)", color: "var(--text)", padding: "12px 14px", fontSize: 14 }}
        />
      )}

      <button className="wizard-cta" onClick={wizard.goNext}>Continuar →</button>
    </div>
  );
}

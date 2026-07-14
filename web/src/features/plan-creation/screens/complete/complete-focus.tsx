"use client";

import { useEffect, useState } from "react";
import { ChoiceGrid } from "@/shared/components/ui/choice-grid";
import { OptionCard } from "@/shared/components/ui/option-card";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import {
  MuscleSelector,
  MusclePriorityControl,
  useMuscleSelection,
} from "@/features/muscle-selector";
import { BODY_FOCUS, TRAINING_STYLES } from "../options";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

export function CompleteFocus({ wizard }: { wizard: PlanCreationWizard }) {
  const { form, set } = wizard;
  const isStrength = form.modality === "musculacao";

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Foco Muscular</h2>

      {isStrength ? (
        <StrengthFocus wizard={wizard} />
      ) : (
        <>
          <p className="wizard-sub">Escolha até três focos musculares para priorizar.</p>
          <ChoiceGrid
            values={BODY_FOCUS}
            selected={form.preferred_body_focus}
            limit={3}
            onToggle={(value) => {
              const active = form.preferred_body_focus.includes(value);
              if (active) { set("preferred_body_focus", form.preferred_body_focus.filter((item) => item !== value)); return; }
              if (form.preferred_body_focus.length >= 3) return;
              set("preferred_body_focus", [...form.preferred_body_focus, value]);
            }}
          />
        </>
      )}

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

      <button className="wizard-cta" onClick={wizard.goNext}>Continuar configuração →</button>
      <button className="wizard-back" onClick={wizard.goNext}>Pular agora</button>
    </div>
  );
}

// Seletor muscular completo (corpo + cards + presets) com modo avançado de
// prioridades. Sincroniza a seleção de volta ao form do wizard.
function StrengthFocus({ wizard }: { wizard: PlanCreationWizard }) {
  const { form, set } = wizard;
  const [advanced, setAdvanced] = useState(Object.keys(form.muscle_priorities).length > 0);
  const selection = useMuscleSelection({
    initialSelected: form.selected_muscles,
    initialPriorities: form.muscle_priorities,
  });

  // Persiste a seleção no form (sobrevive a voltar/avançar na mesma sessão).
  useEffect(() => {
    set("selected_muscles", selection.selectedList);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selection.selectedList]);

  useEffect(() => {
    set("muscle_priorities", selection.priorities);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selection.priorities]);

  return (
    <>
      <p className="wizard-sub">Escolha os grupos musculares que você quer treinar.</p>
      <MuscleSelector selection={selection} />

      <button
        type="button"
        className="wizard-back"
        style={{ marginTop: 8 }}
        onClick={() => setAdvanced((v) => !v)}
      >
        {advanced ? "Ocultar divisão e prioridades" : "Ajustar divisão e prioridades"}
      </button>

      {advanced && (
        <div style={{ marginTop: 8 }}>
          <p className="wizard-sub">Prioridade por grupo (Alta treina mais volume; Evitar exclui).</p>
          <MusclePriorityControl
            selected={selection.selectedList}
            priorities={selection.priorities}
            onChange={selection.setPriority}
          />
        </div>
      )}
    </>
  );
}

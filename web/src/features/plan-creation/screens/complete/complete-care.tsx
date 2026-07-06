"use client";

import { ExercisePreferencePicker } from "@/features/profile/exercise-preference-picker";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

export function CompleteCare({ wizard, onFinish }: { wizard: PlanCreationWizard; onFinish: () => void }) {
  const { form, set } = wizard;

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Preferências de exercício</h2>
      <p className="wizard-sub">Opcional — você pode pular e ajustar depois.</p>

      <div style={{ display: "grid", gap: 18 }}>
        <ExercisePreferencePicker
          label="Exercícios favoritos"
          hint="Vamos priorizá-los no seu plano."
          selected={form.favorite_exercises}
          onChange={(exercises) => set("favorite_exercises", exercises)}
        />
        <ExercisePreferencePicker
          label="Exercícios a evitar"
          hint="Não vamos priorizá-los nas próximas estratégias."
          selected={form.avoided_exercises}
          onChange={(exercises) => set("avoided_exercises", exercises)}
        />
      </div>

      <p style={{ marginTop: 18, fontSize: 12, color: "var(--text-muted)" }}>
        A EasyHealth não substitui orientação médica. Se você sente dor ou tem condição de saúde, consulte um profissional.
      </p>

      <button className="wizard-cta" onClick={onFinish}>Gerar meu plano ✨</button>
      <button className="wizard-back" onClick={onFinish}>Pular por enquanto</button>
    </div>
  );
}

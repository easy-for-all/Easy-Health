"use client";

import { useEffect } from "react";
import { OptionCard } from "@/shared/components/ui/option-card";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import { trackOnboardingEvent } from "@/shared/lib/onboarding-tracking";
import type { WorkoutPeriod } from "../../types";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

// Suggested (editable) default local time per period. "variable" has none.
const PERIODS: { value: WorkoutPeriod; icon: string; label: string; time: string }[] = [
  { value: "morning", icon: "🌅", label: "De manhã", time: "07:00" },
  { value: "lunch", icon: "🥗", label: "No horário do almoço", time: "12:30" },
  { value: "afternoon", icon: "☀️", label: "À tarde", time: "16:00" },
  { value: "evening", icon: "🌙", label: "À noite", time: "19:00" },
  { value: "variable", icon: "🔀", label: "Meu horário varia", time: "" },
];

// 05:00 → 22:00 in 30-min steps — simple, mobile-friendly, no seconds.
const TIME_OPTIONS: string[] = Array.from({ length: (22 - 5) * 2 + 1 }, (_, i) => {
  const minutes = 5 * 60 + i * 30;
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
});

export function WhenStep({ wizard }: { wizard: PlanCreationWizard }) {
  const { form, set } = wizard;

  useEffect(() => {
    trackOnboardingEvent("workout_time_step_viewed", { onboardingFlow: wizard.mode });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function selectPeriod(period: WorkoutPeriod, defaultTime: string) {
    set("preferred_workout_period", period);
    set("preferred_workout_time", period === "variable" ? "" : defaultTime);
  }

  function handleContinue() {
    if (!form.preferred_workout_period) {
      trackOnboardingEvent("workout_time_skipped", { onboardingFlow: wizard.mode });
    } else {
      trackOnboardingEvent("workout_time_selected", {
        onboardingFlow: wizard.mode,
        metadata: {
          period: form.preferred_workout_period,
          has_exact_time: Boolean(form.preferred_workout_time),
          source: "onboarding",
        },
      });
    }
    wizard.goNext();
  }

  const showTimePicker = Boolean(form.preferred_workout_period) && form.preferred_workout_period !== "variable";

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={wizard.goBack} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>
      <h2 className="wizard-title">Quando você costuma treinar?</h2>
      <p className="wizard-sub">
        Usaremos isso para organizar melhor seu plano e, se você quiser, lembrar no horário certo.
      </p>

      <div style={{ display: "grid", gap: 10 }}>
        {PERIODS.map((p) => (
          <OptionCard
            key={p.value}
            icon={p.icon}
            label={p.label}
            description={p.time ? `Sugerido: ${p.time}` : undefined}
            selected={form.preferred_workout_period === p.value}
            onClick={() => selectPeriod(p.value, p.time)}
          />
        ))}
      </div>

      {showTimePicker && (
        <div style={{ marginTop: 20 }}>
          <label className="wizard-sub" htmlFor="preferred-time" style={{ display: "block", marginBottom: 8 }}>
            Por volta de que horas?
          </label>
          <select
            id="preferred-time"
            className="wizard-select"
            value={form.preferred_workout_time || ""}
            onChange={(e) => set("preferred_workout_time", e.target.value)}
          >
            {TIME_OPTIONS.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
        </div>
      )}

      <button className="wizard-cta" onClick={handleContinue}>Continuar →</button>
    </div>
  );
}

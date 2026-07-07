"use client";

import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import { BottomSheet } from "@/shared/components/ui/bottom-sheet";
import { ChoiceGrid } from "@/shared/components/ui/choice-grid";
import { useToast } from "@/shared/components/ui/toast-provider";
import { trackOnboardingEvent } from "@/shared/lib/onboarding-tracking";
import type { Equipment, HealthProfile, IntensityPreference, TrainingStyle } from "@/shared/types/health-profile";

type PromptKey = "rate" | "equipment" | "avoid_exercise" | "style";
const ORDER: PromptKey[] = ["rate", "equipment", "avoid_exercise", "style"];

// Mapeia as chaves internas (já em produção) para os nomes de question_key usados na analytics.
const QUESTION_KEYS: Record<PromptKey, string> = {
  rate: "workout_difficulty_feedback",
  equipment: "available_equipment",
  avoid_exercise: "avoid_exercise",
  style: "training_preference",
};

const EQUIPMENT_OPTIONS: { value: Equipment; label: string }[] = [
  { value: "dumbbell", label: "Halteres" }, { value: "resistance_band", label: "Elástico" },
  { value: "barbell", label: "Barra" }, { value: "machine", label: "Máquinas" },
  { value: "bodyweight", label: "Peso corporal" }, { value: "none", label: "Nenhum" },
];

const STYLE_OPTIONS: { value: TrainingStyle; label: string }[] = [
  { value: "short_sessions", label: "Mais curto" }, { value: "traditional_strength", label: "Mais intenso" },
  { value: "mobility", label: "Mais leve" }, { value: "calisthenics", label: "Mais musculação" },
  { value: "cardio", label: "Mais cardio" }, { value: "mixed", label: "Misturado" },
];

interface TodayExercise {
  exercise_id: number;
  name: string;
}

export function ProgressiveProfilingSheet({
  open, onClose, todayExercises,
}: {
  open: boolean;
  onClose: () => void;
  todayExercises: TodayExercise[];
}) {
  const { show } = useToast();
  const [answered, setAnswered] = useState<Record<string, string> | null>(null);
  const [avoidedIds, setAvoidedIds] = useState<number[]>([]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    api.get<HealthProfile>("/api/v1/health_profile")
      .then((profile) => {
        setAnswered(profile.profiling_prompts_answered ?? {});
        setAvoidedIds(profile.avoided_exercise_ids ?? []);
      })
      .catch(() => onClose());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  function isApplicable(key: PromptKey): boolean {
    if (key === "avoid_exercise") return todayExercises.length > 0;
    return true;
  }

  const promptKey = answered
    ? ORDER.find((key) => isApplicable(key) && !(key in answered)) ?? null
    : null;

  useEffect(() => {
    if (open && answered !== null && promptKey === null) onClose();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, answered, promptKey]);

  useEffect(() => {
    if (open && promptKey) {
      trackOnboardingEvent("progressive_question_shown", { stepName: QUESTION_KEYS[promptKey] });
    }
  }, [open, promptKey]);

  async function persist(key: PromptKey, patch: Record<string, unknown>) {
    setSaving(true);
    try {
      await api.patch("/api/v1/health_profile", {
        ...patch,
        profiling_prompts_answered: { [key]: new Date().toISOString() },
      });
    } catch {
      // best-effort — a próxima sessão tenta de novo se isso falhar
    } finally {
      setSaving(false);
      setAnswered((prev) => ({ ...(prev ?? {}), [key]: new Date().toISOString() }));
    }
  }

  function skip(key: PromptKey) {
    trackOnboardingEvent("progressive_question_skipped", { stepName: QUESTION_KEYS[key] });
    persist(key, {});
  }

  function answerValueFrom(patch: Record<string, unknown>): string {
    const value = Object.values(patch)[0];
    return Array.isArray(value) ? value.join(",") : String(value ?? "");
  }

  function finishWithToast(key: PromptKey, patch: Record<string, unknown>) {
    const answerValue = key === "avoid_exercise" ? "yes" : answerValueFrom(patch);
    trackOnboardingEvent("progressive_question_answered", {
      stepName: QUESTION_KEYS[key],
      metadata: { answer_value: answerValue },
    });
    persist(key, patch).then(() => show("Isso ajuda a ajustar seus próximos treinos ✨", { variant: "good" }));
  }

  if (!promptKey) return null;

  return (
    <BottomSheet open={open} onClose={onClose} ariaLabel="Ajuste rápido pós-treino">
      {promptKey === "rate" && (
        <div>
          <p className="eyebrow" style={{ fontSize: 11.5, fontWeight: 800, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--primary)", margin: "0 0 8px" }}>Depois do treino</p>
          <h2 className="wizard-title">Como foi esse treino?</h2>
          <div className="opts" style={{ marginTop: 12 }}>
            <button className="opt" disabled={saving} onClick={() => finishWithToast("rate", { intensity_preference: "intense" as IntensityPreference })}>
              <span className="otxt"><b>Fácil demais</b></span>
            </button>
            <button className="opt" disabled={saving} onClick={() => finishWithToast("rate", { intensity_preference: "balanced" as IntensityPreference })}>
              <span className="otxt"><b>Na medida</b></span>
            </button>
            <button className="opt" disabled={saving} onClick={() => finishWithToast("rate", { intensity_preference: "easy_start" as IntensityPreference })}>
              <span className="otxt"><b>Difícil demais</b></span>
            </button>
          </div>
        </div>
      )}

      {promptKey === "equipment" && (
        <div>
          <h2 className="wizard-title">Quer deixar seus próximos treinos melhores?</h2>
          <p className="wizard-sub">Você tem algum equipamento disponível?</p>
          <EquipmentPicker
            saving={saving}
            onConfirm={(values) => finishWithToast("equipment", { available_equipment: values })}
          />
        </div>
      )}

      {promptKey === "avoid_exercise" && todayExercises[0] && (
        <div>
          <h2 className="wizard-title">Você quer evitar o {todayExercises[0].name} no futuro?</h2>
          <div className="segmented" style={{ marginTop: 12 }}>
            <button disabled={saving} onClick={() => finishWithToast("avoid_exercise", { avoided_exercise_ids: [...avoidedIds, todayExercises[0].exercise_id] })}>Sim</button>
            <button className="sel" disabled={saving} onClick={() => skip("avoid_exercise")}>Não</button>
          </div>
        </div>
      )}

      {promptKey === "style" && (
        <div>
          <h2 className="wizard-title">Qual tipo de treino você prefere?</h2>
          <div className="opts" style={{ marginTop: 12 }}>
            {STYLE_OPTIONS.map((opt) => (
              <button key={opt.value} className="opt" disabled={saving} onClick={() => finishWithToast("style", { preferred_training_styles: [opt.value] })}>
                <span className="otxt"><b>{opt.label}</b></span>
              </button>
            ))}
          </div>
        </div>
      )}

      <button onClick={() => skip(promptKey)} disabled={saving} className="wizard-back" style={{ marginTop: 16 }}>
        Responder depois
      </button>
      <p style={{ marginTop: 8, fontSize: 12, color: "var(--text-muted)" }}>
        ✨ Isso ajuda a ajustar seus próximos treinos.
      </p>
    </BottomSheet>
  );
}

function EquipmentPicker({ saving, onConfirm }: { saving: boolean; onConfirm: (values: Equipment[]) => void }) {
  const [selected, setSelected] = useState<Equipment[]>([]);

  function toggle(value: Equipment) {
    if (value === "none") { setSelected(["none"]); return; }
    const next = selected.filter((item) => item !== "none");
    setSelected(selected.includes(value) ? next.filter((item) => item !== value) : [...next, value]);
  }

  return (
    <div style={{ marginTop: 12 }}>
      <ChoiceGrid values={EQUIPMENT_OPTIONS} selected={selected} onToggle={toggle} />
      <button className="wizard-cta" disabled={saving || selected.length === 0} onClick={() => onConfirm(selected)}>
        Continuar
      </button>
    </div>
  );
}

"use client";

import type { WorkoutChatPreview } from "./types";
import { AiWorkoutSafetyNotice } from "./ai-workout-safety-notice";
import { AI_CHAT_COLORS } from "./theme";

const MUSCLE_LABELS: Record<string, string> = {
  chest: "Peito", back: "Costas", shoulders: "Ombros", biceps: "Bíceps",
  triceps: "Tríceps", legs: "Pernas", core: "Core", glutes: "Glúteos",
  calves: "Panturrilha", forearms: "Antebraço", trapezius: "Trapézio",
};

interface Props {
  preview: WorkoutChatPreview;
  confirming: boolean;
  onAdjust: () => void;
  onConfirm: () => void;
}

export function AiWorkoutPreviewCard({ preview, confirming, onAdjust, onConfirm }: Props) {
  return (
    <div
      style={{
        background: AI_CHAT_COLORS.surface,
        border: `1px solid ${AI_CHAT_COLORS.border}`,
        borderRadius: "var(--r-lg)",
        padding: "16px 18px",
        display: "flex",
        flexDirection: "column",
        gap: 12,
        margin: "4px 0 8px",
      }}
    >
      <div>
        <p style={{ fontSize: 11, fontWeight: 700, letterSpacing: ".06em", textTransform: "uppercase", color: AI_CHAT_COLORS.primary, margin: "0 0 4px" }}>
          Prévia do treino
        </p>
        <p style={{ fontSize: 16, fontWeight: 700, margin: 0, color: AI_CHAT_COLORS.text }}>{preview.plan_name}</p>
        {preview.rationale && (
          <p style={{ fontSize: 13, color: AI_CHAT_COLORS.textDim, margin: "6px 0 0" }}>{preview.rationale}</p>
        )}
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        {preview.week_structure.map((day, i) => (
          <div key={`${day.name}-${i}`} style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
            <span style={{ fontSize: 13, fontWeight: 700, color: AI_CHAT_COLORS.text }}>{day.name}</span>
            {day.muscle_groups.map((group) => (
              <span
                key={group}
                style={{ fontSize: 11, fontWeight: 600, padding: "2px 8px", borderRadius: 999, background: AI_CHAT_COLORS.primarySoft, color: AI_CHAT_COLORS.primary }}
              >
                {MUSCLE_LABELS[group] ?? group}
              </span>
            ))}
          </div>
        ))}
      </div>

      <AiWorkoutSafetyNotice notes={preview.safety_notes} />

      <div style={{ display: "flex", gap: 8, marginTop: 4 }}>
        <button
          onClick={onAdjust}
          disabled={confirming}
          style={{
            flex: 1, padding: "10px 0", borderRadius: "var(--r-md)", border: `1px solid ${AI_CHAT_COLORS.border}`,
            background: "transparent", color: AI_CHAT_COLORS.textDim, fontSize: 13, fontWeight: 600,
            cursor: confirming ? "not-allowed" : "pointer", opacity: confirming ? 0.6 : 1,
          }}
        >
          Ajustar plano
        </button>
        <button
          onClick={onConfirm}
          disabled={confirming}
          style={{
            flex: 2, padding: "10px 0", borderRadius: "var(--r-md)", border: "none",
            background: AI_CHAT_COLORS.primary, color: "#fff", fontSize: 13, fontWeight: 700,
            cursor: confirming ? "not-allowed" : "pointer", opacity: confirming ? 0.6 : 1,
          }}
        >
          {confirming ? "Criando treino…" : "Criar meu treino"}
        </button>
      </div>
    </div>
  );
}

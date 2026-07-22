"use client";

import { useState } from "react";
import { trackOnboardingEvent } from "@/shared/lib/onboarding-tracking";
import type { CreationMode } from "../types";

type CreationOption = CreationMode | "photo" | "chat";

const MODE_AVAILABILITY: Record<CreationOption, boolean> = {
  quick: true,
  complete: true,
  photo: false,
  chat: false,
};

interface ModeOption {
  value: CreationOption;
  icon: string;
  title: string;
  badge?: { label: string; tone: "primary" | "good" };
  text: string;
  hint: string;
  disabled?: boolean;
}

const MODES: ModeOption[] = [
  {
    value: "quick", icon: "⚡", title: "Rápido",
    badge: { label: "Recomendado", tone: "primary" },
    text: "Responda poucas perguntas e comece em menos de 30 segundos.",
    hint: "Só 4 perguntas rápidas e seu treino já está pronto.",
  },
  {
    value: "complete", icon: "🧠", title: "Completo",
    text: "Personalize seu plano com mais detalhes desde o início.",
    hint: "Vamos te conhecer melhor — leva de 2 a 3 minutos.",
  },
  {
    value: "photo", icon: "📷", title: "Pela sua foto",
    badge: { label: "EM BREVE", tone: "primary" },
    text: "Use fotos para a IA entender melhor seu corpo e objetivo.",
    hint: "",
  },
  {
    value: "chat", icon: "✨", title: "Conversar com a IA",
    badge: { label: "EM BREVE", tone: "primary" },
    text: "Conte sua rotina, objetivo e limitações em linguagem natural.",
    hint: "",
  },
];

export function CreateStart({ onSelect, onCancel }: { onSelect: (mode: CreationMode) => void; onCancel?: () => void }) {
  const [selected, setSelected] = useState<CreationMode>("quick");
  const safeSelected: CreationMode = MODE_AVAILABILITY[selected] ? selected : "quick";

  return (
    <div>
      {onCancel && <button onClick={onCancel} className="wizard-back">← Voltar</button>}
      <p style={{ fontSize: 11.5, fontWeight: 800, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--primary)", margin: "0 0 8px" }}>
        Criar treino
      </p>
      <h1 className="wizard-title">Como você quer começar?</h1>
      <p className="wizard-sub">Escolha o jeito mais fácil para criar seu primeiro treino.</p>

      <div className="opts">
        {MODES.map((m) => {
          const isEnabled = MODE_AVAILABILITY[m.value];
          const isSelected = isEnabled && safeSelected === m.value;
          return (
            <button
              key={m.value}
              type="button"
              disabled={!isEnabled}
              aria-disabled={!isEnabled}
              onClick={() => {
                if (!isEnabled) return;
                setSelected(m.value as CreationMode);
              }}
              className={`opt${isSelected ? " sel" : ""}`}
              style={!isEnabled ? { opacity: 0.55, cursor: "not-allowed" } : undefined}
            >
              <span className="oicon" style={{ fontSize: 20 }} aria-hidden>{m.icon}</span>
              <span className="otxt">
                <b style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  {m.title}
                  {m.badge && (
                    <span style={{
                      fontSize: 10.5, fontWeight: 800, textTransform: "uppercase", letterSpacing: ".04em",
                      padding: "2px 8px", borderRadius: 999,
                      background: m.badge.tone === "good" ? "var(--good-soft)" : "var(--primary-soft)",
                      color: m.badge.tone === "good" ? "var(--good)" : "var(--primary)",
                    }}>
                      {m.badge.label}
                    </span>
                  )}
                </b>
                <small>{m.text}</small>
                {isSelected && m.hint && (
                  <small style={{ display: "block", marginTop: 6, color: "var(--primary)", fontWeight: 700 }}>
                    ✓ {m.hint}
                  </small>
                )}
              </span>
              <span className="chk" aria-hidden>
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round">
                  <path d="M20 6L9 17l-5-5" />
                </svg>
              </span>
            </button>
          );
        })}
      </div>

      <button
        className="wizard-cta"
        onClick={() => {
          trackOnboardingEvent("onboarding_flow_selected", {
            onboardingFlow: safeSelected,
            stepName: "choose_flow",
            metadata: { selected_option: safeSelected },
          });
          onSelect(safeSelected);
        }}
      >
        Continuar
      </button>
    </div>
  );
}

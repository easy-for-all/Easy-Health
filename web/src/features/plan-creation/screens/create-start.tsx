"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { trackOnboardingEvent } from "@/shared/lib/onboarding-tracking";
import type { CreationMode } from "../types";

interface ModeOption {
  value: CreationMode | "photo" | "chat";
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
    badge: { label: "Em breve", tone: "primary" },
    text: "Use fotos para a IA entender melhor seu corpo e objetivo.",
    hint: "", disabled: true,
  },
  {
    value: "chat", icon: "✨", title: "Conversar com a IA",
    badge: { label: "Novo", tone: "good" },
    text: "Conte sua rotina, objetivo e limitações em linguagem natural.",
    hint: "",
  },
];

export function CreateStart({ onSelect, onCancel }: { onSelect: (mode: CreationMode) => void; onCancel?: () => void }) {
  const [selected, setSelected] = useState<CreationMode>("quick");
  const router = useRouter();

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
          const isSelected = !m.disabled && selected === m.value;
          return (
            <button
              key={m.value}
              type="button"
              disabled={m.disabled}
              onClick={() => {
                if (m.disabled) return;
                if (m.value === "chat") {
                  router.push("/plan/ai-chat");
                  return;
                }
                setSelected(m.value as CreationMode);
              }}
              className={`opt${isSelected ? " sel" : ""}`}
              style={m.disabled ? { opacity: 0.55, cursor: "not-allowed" } : undefined}
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
            onboardingFlow: selected,
            stepName: "choose_flow",
            metadata: { selected_option: selected },
          });
          onSelect(selected);
        }}
      >
        Continuar
      </button>
    </div>
  );
}

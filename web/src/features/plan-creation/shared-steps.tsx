"use client";

import { useEffect, useState } from "react";
import { GeneratingView } from "@/shared/components/generating-view";
import type { Modality } from "./types";

function buildGenerationSteps(modality: Modality): string[] {
  const base = ["Analisando seu perfil", "Configurando dias de treino"];
  if (modality === "cardio" || modality === "misto") {
    base.push("Selecionando exercícios cardio", "Criando progressão de intensidade", "Distribuindo treinos na semana", "Finalizando planejamento");
  } else if (modality === "funcional" || modality === "ai_choice") {
    base.push("Selecionando exercícios funcionais", "Balanceando mobilidade e força", "Distribuindo treinos na semana", "Finalizando planejamento");
  } else {
    base.push("Definindo divisão muscular", "Selecionando exercícios", "Ajustando séries e cargas", "Finalizando planejamento");
  }
  return base;
}

const STEP_MS = 600;

export function GeneratingStep({ modality }: { modality: Modality }) {
  const [steps] = useState(() => buildGenerationSteps(modality));
  const [step, setStep] = useState(0);

  useEffect(() => {
    const interval = setInterval(() => {
      setStep((current) => Math.min(current + 1, steps.length - 1));
    }, STEP_MS);
    return () => clearInterval(interval);
  }, [steps.length]);

  return <GeneratingView step={step} steps={steps} offsetParent />;
}

export function StepHeader({ title, subtitle, onBack }: { title: string; subtitle: string; onBack: () => void }) {
  return (
    <>
      <button onClick={onBack} className="wizard-back">← Voltar</button>
      <h2 className="wizard-title">{title}</h2>
      <p className="wizard-sub">{subtitle}</p>
    </>
  );
}

export function ErrorStep({ error, onRetry, onBack }: { error: string; onRetry: () => void; onBack: () => void }) {
  return (
    <div style={{
      display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center",
      minHeight: "60vh", textAlign: "center", padding: "0 24px",
    }}>
      <div style={{ fontSize: 48, marginBottom: 16 }}>😕</div>
      <h2 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: "0 0 8px" }}>
        Não conseguimos gerar seu plano
      </h2>
      <p style={{ fontSize: 14, color: "var(--text-muted)", margin: "0 0 24px", maxWidth: 320 }}>
        {error || "Ocorreu um erro inesperado. Você pode tentar novamente."}
      </p>
      <button onClick={onRetry} className="wizard-cta" style={{ maxWidth: 320, marginTop: 0, marginBottom: 12 }}>
        Tentar novamente
      </button>
      <button
        onClick={onBack}
        style={{
          width: "100%", maxWidth: 320, padding: "12px", borderRadius: "var(--r-lg)",
          background: "var(--surface)", color: "var(--text-muted)", fontWeight: 600, fontSize: 14,
          border: "1px solid var(--border)", cursor: "pointer",
        }}
      >
        ← Voltar
      </button>
    </div>
  );
}

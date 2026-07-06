"use client";

import { useState } from "react";
import { OptionCard } from "@/shared/components/ui/option-card";
import { ProgressDots } from "@/shared/components/ui/progress-dots";
import type { CardioFormat, CardioType, Modality, SplitType } from "../../types";
import type { PlanCreationWizard } from "../../use-plan-creation-wizard";

// Cascata interna: modalidade → (split | cardio_type → cardio_format) → resolve.
// Só avança o wizard principal (wizard.goNext) quando a cascata termina — mantém uma única
// posição na barra de progresso para o passo "Modalidade", como no protótipo.
type MicroStep = "modality" | "split" | "cardio_type" | "cardio_format";

const MODALITY_OPTIONS: { value: Modality; label: string; icon: string; desc: string }[] = [
  { value: "musculacao", label: "Musculação", icon: "🏋️", desc: "Treino com pesos, barras e máquinas." },
  { value: "cardio", label: "Cardio", icon: "❤️", desc: "Corrida, bike, elíptico e mais." },
  { value: "misto", label: "Musculação + Cardio", icon: "⚡", desc: "Combinação de força e resistência." },
  { value: "funcional", label: "Funcional", icon: "🤸", desc: "Kettlebell, corda e movimentos naturais." },
  { value: "ai_choice", label: "IA escolhe", icon: "🤖", desc: "A IA monta o melhor formato para você." },
];

const SPLIT_OPTIONS: { value: SplitType; label: string; icon: string; desc: string }[] = [
  { value: "ai_choice", label: "IA decide", icon: "🤖", desc: "A IA escolhe a melhor divisão para seu perfil." },
  { value: "full_body", label: "Full Body", icon: "💪", desc: "Corpo todo em cada sessão." },
  { value: "upper_lower", label: "Superiores / Inferiores", icon: "⬆️", desc: "Alterna entre parte superior e inferior." },
  { value: "ab", label: "AB", icon: "🔄", desc: "Dois treinos alternados (A e B)." },
  { value: "abc", label: "ABC", icon: "🔤", desc: "Três treinos em rotação (A, B e C)." },
  { value: "ppl", label: "Push / Pull / Legs", icon: "🏋️", desc: "Empurrar, puxar e pernas separados." },
];

const CARDIO_TYPE_OPTIONS: { value: CardioType; label: string; icon: string; desc: string }[] = [
  { value: "corrida", label: "Corrida", icon: "🏃", desc: "Esteira ou rua." },
  { value: "caminhada", label: "Caminhada", icon: "🚶", desc: "Caminhada ativa ou em inclinação." },
  { value: "bicicleta", label: "Bike", icon: "🚲", desc: "Bike estacionária ou ao ar livre." },
  { value: "hiit", label: "HIIT", icon: "🔥", desc: "Alta intensidade com intervalos." },
  { value: "natacao", label: "Natação", icon: "🏊", desc: "Nado livre, borboleta e mais." },
  { value: "ai_choice", label: "IA escolhe", icon: "🤖", desc: "A IA decide o melhor cardio." },
];

const CARDIO_FORMAT_OPTIONS: { value: CardioFormat; label: string; icon: string; desc: string }[] = [
  { value: "ai_choice", label: "IA decide", icon: "🤖", desc: "A IA escolhe o formato ideal." },
  { value: "continuo_leve", label: "Contínuo leve", icon: "🌱", desc: "Ritmo baixo, longa duração." },
  { value: "continuo_moderado", label: "Contínuo moderado", icon: "🎯", desc: "Intensidade média sustentada." },
  { value: "intervalado", label: "Intervalado", icon: "🔄", desc: "Alternância de esforço e descanso." },
  { value: "progressivo", label: "Progressivo", icon: "📈", desc: "Intensidade aumenta ao longo da sessão." },
];

export function CompleteMethod({ wizard }: { wizard: PlanCreationWizard }) {
  const [micro, setMicro] = useState<MicroStep>("modality");
  const { form, set } = wizard;

  function backMicro() {
    if (micro === "modality") { wizard.goBack(); return; }
    if (micro === "cardio_format") { setMicro("cardio_type"); return; }
    if (micro === "split" || micro === "cardio_type") { setMicro("modality"); return; }
  }

  function selectModality(value: Modality) {
    set("modality", value);
    if (value === "musculacao") { setMicro("split"); return; }
    if (value === "misto") { setMicro("split"); return; }
    if (value === "cardio") { setMicro("cardio_type"); return; }
    wizard.goNext(); // funcional / ai_choice não têm sub-passos
  }

  function selectSplit(value: SplitType) {
    set("split_type", value);
    if (form.modality === "misto") { setMicro("cardio_type"); return; }
    wizard.goNext();
  }

  function selectCardioType(value: CardioType) {
    set("cardio_type", value);
    setMicro("cardio_format");
  }

  function selectCardioFormat(value: CardioFormat) {
    set("cardio_format", value);
    wizard.goNext();
  }

  return (
    <div>
      <ProgressDots total={wizard.progress.total} current={wizard.progress.current} />
      <button onClick={backMicro} className="wizard-back" style={{ marginTop: 20 }}>← Voltar</button>

      {micro === "modality" && (
        <>
          <h2 className="wizard-title">Qual modalidade?</h2>
          <p className="wizard-sub">Escolha o tipo de treino que você quer focar.</p>
          <div className="opts">
            {MODALITY_OPTIONS.map((opt) => (
              <OptionCard key={opt.value} icon={opt.icon} label={opt.label} description={opt.desc}
                selected={form.modality === opt.value} onClick={() => selectModality(opt.value)} />
            ))}
          </div>
        </>
      )}

      {micro === "split" && (
        <>
          <h2 className="wizard-title">Como quer organizar?</h2>
          <p className="wizard-sub">Escolha a divisão de musculação que prefere.</p>
          <div className="opts">
            {SPLIT_OPTIONS.map((opt) => (
              <OptionCard key={opt.value} icon={opt.icon} label={opt.label} description={opt.desc}
                selected={form.split_type === opt.value} onClick={() => selectSplit(opt.value)} />
            ))}
          </div>
        </>
      )}

      {micro === "cardio_type" && (
        <>
          <h2 className="wizard-title">Que tipo de cardio?</h2>
          <p className="wizard-sub">Selecione a modalidade de cardio preferida.</p>
          <div className="opts">
            {CARDIO_TYPE_OPTIONS.map((opt) => (
              <OptionCard key={opt.value} icon={opt.icon} label={opt.label} description={opt.desc}
                selected={form.cardio_type === opt.value} onClick={() => selectCardioType(opt.value)} />
            ))}
          </div>
        </>
      )}

      {micro === "cardio_format" && (
        <>
          <h2 className="wizard-title">Como prefere fazer?</h2>
          <p className="wizard-sub">Escolha o formato do treino de cardio.</p>
          <div className="opts">
            {CARDIO_FORMAT_OPTIONS.map((opt) => (
              <OptionCard key={opt.value} icon={opt.icon} label={opt.label} description={opt.desc}
                selected={form.cardio_format === opt.value} onClick={() => selectCardioFormat(opt.value)} />
            ))}
          </div>
        </>
      )}
    </div>
  );
}

"use client";

import { MuscleSelector, type MuscleSelection } from "@/features/muscle-selector";

// Passo "Foco muscular" do Treino Rápido — só renderizado quando a modalidade é
// força (musculação). "Decida por mim" avança sem seleção (backend decide).
export function MuscleStep({
  selection,
  onContinue,
  onDecideForMe,
}: {
  selection: MuscleSelection;
  onContinue: () => void;
  onDecideForMe: () => void;
}) {
  const empty = selection.count === 0;

  return (
    <div>
      <MuscleSelector selection={selection} />

      <button
        onClick={onDecideForMe}
        className="mt-2 w-full rounded-2xl border border-slate-700 py-3 text-sm font-semibold text-slate-300"
      >
        Decida por mim
      </button>

      {empty && (
        <p className="mt-3 text-xs text-slate-400 text-center">
          Escolha pelo menos um grupo ou selecione &quot;Decida por mim&quot;.
        </p>
      )}

      <button
        disabled={empty}
        onClick={onContinue}
        className="mt-4 w-full rounded-2xl py-4 text-base font-semibold text-white disabled:opacity-40"
        style={{ background: "var(--primary)" }}
      >
        Continuar →
      </button>
    </div>
  );
}

"use client";

import { MUSCLE_GROUPS, type MuscleGroupId } from "./muscle-data";
import "./muscle-selector.css";

export function MuscleSelectionSummary({
  selected,
  onRemove,
  onClear,
}: {
  selected: MuscleGroupId[];
  onRemove: (id: MuscleGroupId) => void;
  onClear: () => void;
}) {
  if (selected.length === 0) {
    return (
      <div className="ms-summary">
        <span className="ms-summary-empty">Nenhum grupo selecionado ainda.</span>
      </div>
    );
  }

  return (
    <div className="ms-summary" role="group" aria-label="Grupos selecionados">
      {selected.map((id) => (
        <span key={id} className="ms-chip">
          {MUSCLE_GROUPS[id].name_pt}
          <button
            type="button"
            aria-label={`Remover ${MUSCLE_GROUPS[id].name_pt}`}
            onClick={() => onRemove(id)}
          >
            ×
          </button>
        </span>
      ))}
      <button type="button" className="ms-clear" onClick={onClear}>
        Limpar
      </button>
    </div>
  );
}

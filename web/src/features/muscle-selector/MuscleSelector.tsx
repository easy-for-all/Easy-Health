"use client";

import { SegmentedControl } from "@/shared/components/ui/segmented-control";
import { MuscleBodySelector } from "./MuscleBodySelector";
import { MuscleGroupGrid } from "./MuscleGroupGrid";
import { MuscleQuickPreset } from "./MuscleQuickPreset";
import { MuscleSelectionSummary } from "./MuscleSelectionSummary";
import type { BodyView } from "./muscle-data";
import type { MuscleSelection } from "./use-muscle-selection";

const VIEW_OPTIONS: { value: BodyView; label: string }[] = [
  { value: "front", label: "Frente" },
  { value: "back", label: "Costas" },
];

// Bloco reutilizável (Treino Rápido e Completo): corpo interativo + toggle
// Frente/Costas + resumo com chips + cards por categoria + presets.
// A sincronização vem toda de `selection.selected` (fonte única).
export function MuscleSelector({
  selection,
  showPresets = true,
}: {
  selection: MuscleSelection;
  showPresets?: boolean;
}) {
  return (
    <div>
      {showPresets && (
        <div style={{ marginBottom: 14 }}>
          <p className="wizard-sub" style={{ marginBottom: 8 }}>Atalhos rápidos</p>
          <MuscleQuickPreset onApply={(groups) => selection.applyPreset(groups)} />
        </div>
      )}

      <SegmentedControl
        options={VIEW_OPTIONS}
        value={selection.currentView}
        onChange={selection.setView}
      />

      <MuscleBodySelector
        view={selection.currentView}
        isSelected={selection.isSelected}
        onToggle={selection.toggle}
      />

      <MuscleSelectionSummary
        selected={selection.selectedList}
        onRemove={selection.removeChip}
        onClear={selection.clear}
      />

      <MuscleGroupGrid
        isSelected={selection.isSelected}
        onToggle={selection.toggle}
      />
    </div>
  );
}

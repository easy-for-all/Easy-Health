"use client";

import { SegmentedControl } from "@/shared/components/ui/segmented-control";
import {
  MUSCLE_GROUPS,
  PRIORITY_OPTIONS,
  type MuscleGroupId,
  type MusclePriorities,
  type MusclePriority,
} from "./muscle-data";
import "./muscle-selector.css";

// Modo avançado (Treino Completo): define Alta / Normal / Evitar por grupo
// selecionado. Default implícito é "normal".
export function MusclePriorityControl({
  selected,
  priorities,
  onChange,
}: {
  selected: MuscleGroupId[];
  priorities: MusclePriorities;
  onChange: (id: MuscleGroupId, priority: MusclePriority) => void;
}) {
  if (selected.length === 0) return null;

  return (
    <div>
      {selected.map((id) => (
        <div key={id} className="ms-priority-row">
          <span className="ms-priority-name">{MUSCLE_GROUPS[id].name_pt}</span>
          <SegmentedControl
            options={PRIORITY_OPTIONS}
            value={priorities[id] ?? "normal"}
            onChange={(value) => onChange(id, value)}
          />
        </div>
      ))}
    </div>
  );
}

"use client";

import { PRESETS, type MuscleGroupId } from "./muscle-data";
import "./muscle-selector.css";

export function MuscleQuickPreset({
  onApply,
}: {
  onApply: (groups: MuscleGroupId[]) => void;
}) {
  return (
    <div className="ms-presets">
      {PRESETS.map((preset) => (
        <button
          key={preset.id}
          type="button"
          className="ms-preset"
          onClick={() => onApply(preset.groups)}
        >
          {preset.label}
        </button>
      ))}
    </div>
  );
}

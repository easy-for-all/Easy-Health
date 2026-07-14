"use client";

import { OptionCard } from "@/shared/components/ui/option-card";
import {
  CATEGORY_LABELS,
  groupsByCategory,
  type MuscleCategory,
  type MuscleGroupId,
} from "./muscle-data";

const CATEGORY_ORDER: MuscleCategory[] = ["upper", "core", "lower"];

export function MuscleGroupGrid({
  isSelected,
  onToggle,
}: {
  isSelected: (id: MuscleGroupId) => boolean;
  onToggle: (id: MuscleGroupId) => void;
}) {
  return (
    <div>
      {CATEGORY_ORDER.map((category) => {
        const groups = groupsByCategory(category);
        if (groups.length === 0) return null;
        return (
          <div key={category} style={{ marginBottom: 16 }}>
            <p className="wizard-sub" style={{ marginBottom: 8 }}>{CATEGORY_LABELS[category]}</p>
            <div className="opt-grid">
              {groups.map((group) => (
                <OptionCard
                  key={group.id}
                  label={group.name_pt}
                  selected={isSelected(group.id)}
                  onClick={() => onToggle(group.id)}
                />
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

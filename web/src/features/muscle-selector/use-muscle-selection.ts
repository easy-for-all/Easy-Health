"use client";

import { useCallback, useMemo, useState } from "react";
import {
  MUSCLE_GROUP_IDS,
  type BodyView,
  type MuscleGroupId,
  type MusclePriorities,
  type MusclePriority,
} from "./muscle-data";

// Origem da última seleção — usada só para analytics.
export type SelectionSource = "body" | "card" | "preset" | "recommendation" | "decide_for_me";

export interface UseMuscleSelectionOptions {
  initialSelected?: MuscleGroupId[];
  initialView?: BodyView;
  initialPriorities?: MusclePriorities;
}

// Estado único da seleção muscular. `selected` é a fonte de verdade: corpo,
// cards e resumo leem/escrevem o mesmo Set, garantindo sincronização
// bidirecional sem estados paralelos. A persistência (ex.: no form do wizard)
// e a analytics ficam a cargo do consumidor, observando `selectedList`.
export function useMuscleSelection(options: UseMuscleSelectionOptions = {}) {
  const [selected, setSelected] = useState<Set<MuscleGroupId>>(
    () => new Set(options.initialSelected ?? []),
  );
  const [currentView, setCurrentView] = useState<BodyView>(options.initialView ?? "front");
  const [priorities, setPriorities] = useState<MusclePriorities>(options.initialPriorities ?? {});

  const isSelected = useCallback((id: MuscleGroupId) => selected.has(id), [selected]);

  const toggle = useCallback((id: MuscleGroupId) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const removeChip = useCallback((id: MuscleGroupId) => {
    setSelected((prev) => {
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
    // Prioridade órfã não faz sentido: limpa junto.
    setPriorities((prev) => {
      if (!(id in prev)) return prev;
      const next = { ...prev };
      delete next[id];
      return next;
    });
  }, []);

  const clear = useCallback(() => {
    setSelected(new Set());
    setPriorities({});
  }, []);

  // Presets unem grupos à seleção atual (nunca removem).
  const applyPreset = useCallback((groups: MuscleGroupId[]) => {
    setSelected((prev) => {
      const next = new Set(prev);
      groups.forEach((g) => next.add(g));
      return next;
    });
  }, []);

  const setPriority = useCallback((id: MuscleGroupId, priority: MusclePriority) => {
    setPriorities((prev) => ({ ...prev, [id]: priority }));
  }, []);

  const selectedList = useMemo<MuscleGroupId[]>(
    () => MUSCLE_GROUP_IDS.filter((id) => selected.has(id)),
    [selected],
  );

  return {
    selected,
    selectedList,
    currentView,
    priorities,
    isSelected,
    toggle,
    removeChip,
    clear,
    applyPreset,
    setView: setCurrentView,
    setPriority,
    count: selected.size,
  };
}

export type MuscleSelection = ReturnType<typeof useMuscleSelection>;

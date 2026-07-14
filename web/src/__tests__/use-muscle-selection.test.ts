import { act, renderHook } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { useMuscleSelection } from "@/features/muscle-selector/use-muscle-selection";
import {
  BODY_SHAPES,
  MUSCLE_GROUP_IDS,
  PRESETS,
} from "@/features/muscle-selector/muscle-data";

describe("useMuscleSelection", () => {
  it("toggles a group on and off", () => {
    const { result } = renderHook(() => useMuscleSelection());

    act(() => result.current.toggle("chest"));
    expect(result.current.isSelected("chest")).toBe(true);
    expect(result.current.selectedList).toEqual(["chest"]);
    expect(result.current.count).toBe(1);

    act(() => result.current.toggle("chest"));
    expect(result.current.isSelected("chest")).toBe(false);
    expect(result.current.count).toBe(0);
  });

  it("keeps selectedList in canonical group order regardless of selection order", () => {
    const { result } = renderHook(() => useMuscleSelection());

    act(() => result.current.toggle("legs"));
    act(() => result.current.toggle("chest"));

    // chest precede legs em MUSCLE_GROUP_IDS.
    expect(result.current.selectedList).toEqual(["chest", "legs"]);
  });

  it("unions preset groups into the current selection without removing", () => {
    const { result } = renderHook(() => useMuscleSelection());
    const legsFull = PRESETS.find((p) => p.id === "legs_full")!;

    act(() => result.current.toggle("chest"));
    act(() => result.current.applyPreset(legsFull.groups));

    expect(result.current.selectedList).toEqual(
      expect.arrayContaining(["chest", ...legsFull.groups]),
    );
  });

  it("removes a chip and clears its orphan priority", () => {
    const { result } = renderHook(() =>
      useMuscleSelection({ initialSelected: ["chest", "back"] }),
    );

    act(() => result.current.setPriority("chest", "high"));
    expect(result.current.priorities.chest).toBe("high");

    act(() => result.current.removeChip("chest"));
    expect(result.current.isSelected("chest")).toBe(false);
    expect(result.current.priorities.chest).toBeUndefined();
  });

  it("clears everything", () => {
    const { result } = renderHook(() =>
      useMuscleSelection({ initialSelected: ["chest", "legs"] }),
    );

    act(() => result.current.setPriority("legs", "avoid"));
    act(() => result.current.clear());

    expect(result.current.count).toBe(0);
    expect(result.current.priorities).toEqual({});
  });
});

describe("muscle body map", () => {
  it("only maps regions to the 11 real backend groups", () => {
    const shapeGroups = [...BODY_SHAPES.front, ...BODY_SHAPES.back].map((s) => s.group);
    for (const group of shapeGroups) {
      expect(MUSCLE_GROUP_IDS).toContain(group);
    }
  });

  it("covers every selectable group with at least one body region", () => {
    const shapeGroups = new Set(
      [...BODY_SHAPES.front, ...BODY_SHAPES.back].map((s) => s.group),
    );
    for (const group of MUSCLE_GROUP_IDS) {
      expect(shapeGroups.has(group)).toBe(true);
    }
  });
});

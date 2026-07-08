export const MUSCLE_LABELS: Record<string, string> = {
  chest: "Peito",
  back: "Costas",
  shoulders: "Ombros",
  biceps: "Bíceps",
  triceps: "Tríceps",
  legs: "Pernas",
  core: "Core",
  forearms: "Antebraços",
  calves: "Panturrilhas",
  glutes: "Glúteos",
  trapezius: "Trapézio",
};

export function muscleLabel(muscleGroup: string): string {
  return MUSCLE_LABELS[muscleGroup] ?? muscleGroup;
}

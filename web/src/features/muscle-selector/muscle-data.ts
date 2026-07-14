// Fonte de verdade do seletor: os 11 grupos musculares que o backend distingue
// de fato (Exercise::MUSCLE_GROUPS). O corpo interativo mostra regiões anatômicas
// mais finas (quadríceps, posteriores, oblíquos, lombar...) que colapsam nesses 11
// grupos — por isso várias formas do SVG podem apontar para o mesmo grupo.

export type MuscleGroupId =
  | "chest" | "back" | "shoulders" | "biceps" | "triceps"
  | "legs" | "core" | "forearms" | "calves" | "glutes" | "trapezius";

export type MuscleCategory = "upper" | "core" | "lower";
export type BodyView = "front" | "back";

export interface MuscleGroup {
  id: MuscleGroupId;
  name_pt: string;
  category: MuscleCategory;
  // Vista onde o grupo é melhor visualizado — usada para sugerir o toggle.
  preferred_view: BodyView;
}

export const MUSCLE_GROUP_IDS: MuscleGroupId[] = [
  "chest", "back", "shoulders", "biceps", "triceps",
  "legs", "core", "forearms", "calves", "glutes", "trapezius",
];

export const MUSCLE_GROUPS: Record<MuscleGroupId, MuscleGroup> = {
  chest:     { id: "chest",     name_pt: "Peito",        category: "upper", preferred_view: "front" },
  back:      { id: "back",      name_pt: "Costas",       category: "upper", preferred_view: "back" },
  shoulders: { id: "shoulders", name_pt: "Ombros",       category: "upper", preferred_view: "front" },
  biceps:    { id: "biceps",    name_pt: "Bíceps",       category: "upper", preferred_view: "front" },
  triceps:   { id: "triceps",   name_pt: "Tríceps",      category: "upper", preferred_view: "back" },
  forearms:  { id: "forearms",  name_pt: "Antebraços",   category: "upper", preferred_view: "front" },
  trapezius: { id: "trapezius", name_pt: "Trapézio",     category: "upper", preferred_view: "back" },
  core:      { id: "core",      name_pt: "Core",         category: "core",  preferred_view: "front" },
  legs:      { id: "legs",      name_pt: "Pernas",       category: "lower", preferred_view: "front" },
  glutes:    { id: "glutes",    name_pt: "Glúteos",      category: "lower", preferred_view: "back" },
  calves:    { id: "calves",    name_pt: "Panturrilhas", category: "lower", preferred_view: "back" },
};

export const CATEGORY_LABELS: Record<MuscleCategory, string> = {
  upper: "Parte superior",
  core: "Core",
  lower: "Parte inferior",
};

export function groupsByCategory(category: MuscleCategory): MuscleGroup[] {
  return MUSCLE_GROUP_IDS.map((id) => MUSCLE_GROUPS[id]).filter((g) => g.category === category);
}

// Presets ("atalhos rápidos") — expandem para ids dos 11 grupos.
export interface MusclePreset {
  id: string;
  label: string;
  groups: MuscleGroupId[];
}

export const PRESETS: MusclePreset[] = [
  { id: "chest_triceps",  label: "Peito + Tríceps",  groups: ["chest", "triceps"] },
  { id: "back_biceps",    label: "Costas + Bíceps",  groups: ["back", "biceps"] },
  { id: "legs_full",      label: "Pernas Completas", groups: ["legs", "glutes", "calves"] },
  { id: "shoulders_arms", label: "Ombros + Braços",  groups: ["shoulders", "biceps", "triceps", "forearms"] },
  { id: "full_body",      label: "Corpo Inteiro",    groups: [...MUSCLE_GROUP_IDS] },
];

// ---- Corpo interativo (SVG) ----
// Portado de design_handoff_muscle_selector/muscle-selector-system.html (BODY_SVG),
// com as regiões finas remapeadas para os 11 grupos: abs/obliques/lower_back → core,
// quads/hamstrings → legs, e a região "neck" descartada (não existe no DB).

export type SvgTag = "rect" | "ellipse" | "circle" | "path";

export interface BodyShape {
  group: MuscleGroupId;
  tag: SvgTag;
  attrs: Record<string, string | number>;
}

// Cabeça (não interativa) desenhada como referência anatômica.
export const BODY_HEAD: Record<BodyView, { cx: number; cy: number; r: number }> = {
  front: { cx: 60, cy: 20, r: 14 },
  back: { cx: 60, cy: 20, r: 14 },
};

export const BODY_SHAPES: Record<BodyView, BodyShape[]> = {
  front: [
    { group: "chest",     tag: "ellipse", attrs: { cx: 60, cy: 65, rx: 28, ry: 30 } },
    { group: "shoulders", tag: "circle",  attrs: { cx: 31, cy: 45, r: 11 } },
    { group: "shoulders", tag: "circle",  attrs: { cx: 89, cy: 45, r: 11 } },
    { group: "biceps",    tag: "rect",    attrs: { x: 17, y: 55, width: 13, height: 38, rx: 6 } },
    { group: "biceps",    tag: "rect",    attrs: { x: 90, y: 55, width: 13, height: 38, rx: 6 } },
    { group: "forearms",  tag: "rect",    attrs: { x: 15, y: 94, width: 11, height: 32, rx: 5 } },
    { group: "forearms",  tag: "rect",    attrs: { x: 94, y: 94, width: 11, height: 32, rx: 5 } },
    { group: "core",      tag: "rect",    attrs: { x: 48, y: 98, width: 24, height: 30, rx: 4 } },
    { group: "core",      tag: "path",    attrs: { d: "M46 100 q-6 16 -2 28 l6 -2 q-3 -14 2 -26 z" } },
    { group: "core",      tag: "path",    attrs: { d: "M74 100 q6 16 2 28 l-6 -2 q3 -14 -2 -26 z" } },
    { group: "legs",      tag: "rect",    attrs: { x: 36, y: 132, width: 18, height: 68, rx: 9 } },
    { group: "legs",      tag: "rect",    attrs: { x: 66, y: 132, width: 18, height: 68, rx: 9 } },
    { group: "calves",    tag: "rect",    attrs: { x: 38, y: 202, width: 14, height: 42, rx: 7 } },
    { group: "calves",    tag: "rect",    attrs: { x: 68, y: 202, width: 14, height: 42, rx: 7 } },
  ],
  back: [
    { group: "trapezius", tag: "path",    attrs: { d: "M33 44 Q60 34 87 44 L82 66 Q60 58 38 66 Z" } },
    { group: "back",      tag: "path",    attrs: { d: "M38 66 Q60 58 82 66 L80 118 Q60 126 40 118 Z" } },
    { group: "core",      tag: "rect",    attrs: { x: 44, y: 120, width: 32, height: 24, rx: 4 } },
    { group: "shoulders", tag: "circle",  attrs: { cx: 31, cy: 49, r: 11 } },
    { group: "shoulders", tag: "circle",  attrs: { cx: 89, cy: 49, r: 11 } },
    { group: "triceps",   tag: "rect",    attrs: { x: 17, y: 58, width: 13, height: 38, rx: 6 } },
    { group: "triceps",   tag: "rect",    attrs: { x: 90, y: 58, width: 13, height: 38, rx: 6 } },
    { group: "forearms",  tag: "rect",    attrs: { x: 15, y: 97, width: 11, height: 32, rx: 5 } },
    { group: "forearms",  tag: "rect",    attrs: { x: 94, y: 97, width: 11, height: 32, rx: 5 } },
    { group: "glutes",    tag: "ellipse", attrs: { cx: 49, cy: 150, rx: 12, ry: 15 } },
    { group: "glutes",    tag: "ellipse", attrs: { cx: 71, cy: 150, rx: 12, ry: 15 } },
    { group: "legs",      tag: "rect",    attrs: { x: 37, y: 168, width: 17, height: 46, rx: 9 } },
    { group: "legs",      tag: "rect",    attrs: { x: 66, y: 168, width: 17, height: 46, rx: 9 } },
    { group: "calves",    tag: "rect",    attrs: { x: 38, y: 216, width: 14, height: 42, rx: 7 } },
    { group: "calves",    tag: "rect",    attrs: { x: 68, y: 216, width: 14, height: 42, rx: 7 } },
  ],
};

// Prioridades (modo avançado, só Treino Completo).
export type MusclePriority = "high" | "normal" | "avoid";
export type MusclePriorities = Partial<Record<MuscleGroupId, MusclePriority>>;

export const PRIORITY_OPTIONS: { value: MusclePriority; label: string }[] = [
  { value: "high", label: "Alta" },
  { value: "normal", label: "Normal" },
  { value: "avoid", label: "Evitar" },
];

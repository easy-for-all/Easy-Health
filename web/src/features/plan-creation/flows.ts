import type { CreationMode, StepId } from "./types";

export interface FlowDefinition {
  steps: StepId[];
  first: StepId;
}

// Registro de fluxos por modo. Para adicionar "photo"/"chat" numa entrega futura:
// (1) acrescentar a chave aqui, (2) adicionar os StepIds novos em types.ts,
// (3) criar as telas em screens/photo|chat/, (4) adicionar os cases em plan-creation-flow.tsx.
// O motor de navegação (use-plan-creation-wizard.ts) não muda.
//
// "quick-profile"/"complete-profile" coletam nível + idade/peso/altura/gênero — campos
// obrigatórios (not null) em HealthProfile na criação. Só entram no fluxo quando ainda não
// existe profile (onboarding de usuário novo); no replan o profile já tem esses dados.
const BASE_FLOWS: Record<CreationMode, FlowDefinition> = {
  quick: {
    steps: ["quick-goal", "quick-profile", "quick-place", "quick-time", "quick-when", "quick-limits"],
    first: "quick-goal",
  },
  complete: {
    steps: [
      "complete-goal", "complete-profile", "complete-method", "complete-place",
      "complete-focus", "complete-schedule", "complete-when", "complete-care",
    ],
    first: "complete-goal",
  },
};

const PROFILE_STEP: Record<CreationMode, StepId> = {
  quick: "quick-profile",
  complete: "complete-profile",
};

export interface FlowOptions {
  hasExistingProfile: boolean;
  // Acrescenta o resumo do plano ao final. Usado quando o onboarding roda antes
  // da conta existir: é a tela que entrega valor percebido antes de pedir o
  // cadastro, e por isso conta como uma etapa de verdade do fluxo.
  withPreview?: boolean;
}

export function stepsForMode(mode: CreationMode, { hasExistingProfile, withPreview }: FlowOptions): StepId[] {
  const base = BASE_FLOWS[mode].steps;
  const steps = hasExistingProfile ? base.filter((step) => step !== PROFILE_STEP[mode]) : base;
  return withPreview ? [...steps, "plan-preview"] : steps;
}

export function firstStepForMode(mode: CreationMode, opts: FlowOptions): StepId {
  return stepsForMode(mode, opts)[0];
}

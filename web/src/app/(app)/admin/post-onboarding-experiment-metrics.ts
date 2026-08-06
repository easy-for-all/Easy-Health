// Tipos e helpers puros do bloco "EXPERIMENTO ANDROID — CONTA APÓS O ONBOARDING".
//
// Espelha o payload de GET /api/v1/admin/analytics/post_onboarding_experiment
// (api/app/services/analytics/post_onboarding_experiment.rb). Os nomes seguem
// snake_case de propósito, como no bloco do funil: um valor na tela precisa ser
// rastreável até o serviço sem uma tabela de tradução no meio.
//
// A UNIDADE É UMA INSTALAÇÃO EXPOSTA. Toda taxa aqui tem esse denominador.

import { type Metric } from "./android-installations-metrics";

export type { Metric };

export type ExperimentPeriod = "since_start" | "today" | "7d" | "30d";
export type ExperimentAudience = "external" | "internal_test" | "all";
export type VariantKey = "account_gate" | "open_app";
export type VariantFilter = "all" | VariantKey;

export const VARIANT_KEYS: VariantKey[] = ["account_gate", "open_app"];

export interface MetricScopes {
  same_day?: Metric;
  within_24h?: Metric;
  cumulative?: Metric;
  pending?: number;
}

export interface Difference {
  absolute_pp: number | null;
  relative: number | null;
}

export interface MetricRow {
  key: string;
  label: string;
  unit: string;
  variants: Record<string, MetricScopes | TimingScope>;
  difference?: Partial<Record<"same_day" | "within_24h" | "cumulative", Difference>>;
  note?: string;
}

export interface TimingScope {
  p50_seconds: number | null;
  p90_seconds: number | null;
  sample_size: number;
}

export interface FunnelStage {
  key: string;
  label: string;
  count: number;
  conversion_from_exposed: Metric;
}

export interface VariantFunnel {
  variant: VariantKey;
  label: string;
  exposed: number;
  sample_warning: string;
  stages: FunnelStage[];
}

export interface LastStage {
  variant: VariantKey;
  label: string;
  buckets: { key: string; label: string; count: number }[];
}

export interface ExperimentHeader {
  status: string;
  experiment_key: string;
  min_build: number;
  started_at: string | null;
  expected_split: string;
  assigned_installations: number;
  exposed_installations: number;
  distribution: {
    variant: VariantKey;
    label: string;
    exposed: number;
    share: Metric;
    sample_warning: string;
  }[];
  assigned_without_exposure: Metric;
}

export interface Guardrails {
  events_missing_installation_id: number;
  variant_disagreement: number;
  generation_errors: number;
  claim_failures: Record<string, number>;
  auth_failures: Record<string, number>;
  no_plan_after_exposure: Record<string, Metric>;
  hit_limit_rate: Metric;
  gate_seen_later_rate: Metric;
}

export interface ExperimentPayload {
  source: string;
  generated_at: string;
  experiment_key: string;
  filters: {
    period: ExperimentPeriod;
    build: number | null;
    audience: ExperimentAudience;
    variant: VariantFilter;
  };
  definitions: {
    experiment_key: string;
    min_build: number;
    started_at: string | null;
    unit_note: string;
    window_note: string;
    readout_note: string;
  };
  header: ExperimentHeader;
  metrics: MetricRow[];
  funnels: VariantFunnel[];
  last_stage: LastStage[];
  guardrails: Guardrails;
}

export const PERIOD_OPTIONS: { value: ExperimentPeriod; label: string }[] = [
  { value: "today", label: "Hoje" },
  { value: "7d", label: "7 dias" },
  { value: "30d", label: "30 dias" },
  { value: "since_start", label: "Desde o início" },
];

export const AUDIENCE_OPTIONS: { value: ExperimentAudience; label: string }[] = [
  { value: "external", label: "Externos" },
  { value: "internal_test", label: "Internos/teste" },
  { value: "all", label: "Todos" },
];

export const VARIANT_OPTIONS: { value: VariantFilter; label: string }[] = [
  { value: "all", label: "Todas" },
  { value: "account_gate", label: "Conta antes" },
  { value: "open_app", label: "Abre o app" },
];

export function experimentQuery(filters: {
  period: ExperimentPeriod;
  build: string;
  audience: ExperimentAudience;
  variant: VariantFilter;
}): string {
  const params = new URLSearchParams({
    period: filters.period,
    audience: filters.audience,
    variant: filters.variant,
  });
  if (filters.build) params.set("build", filters.build);
  return params.toString();
}

// Denominador zero vira "—", nunca 0% e nunca infinito. Um 0% afirmaria que
// ninguém converteu; "—" diz que não houve ninguém para converter.
export function formatMetricValue(metric: Metric | undefined): string {
  if (!metric || metric.status === "no_coverage" || metric.denominator === 0) return "—";
  return `${metric.value.toFixed(1)}%`;
}

export function formatMetricWithCounts(metric: Metric | undefined): string {
  if (!metric || metric.status === "no_coverage" || metric.denominator === 0) return "—";
  return `${metric.value.toFixed(1)}% (${metric.numerator}/${metric.denominator})`;
}

export function formatDifference(difference: Difference | undefined): string {
  if (!difference || difference.absolute_pp === null) return "—";

  const signed = difference.absolute_pp > 0 ? `+${difference.absolute_pp}` : `${difference.absolute_pp}`;
  return `${signed} p.p.`;
}

export function formatRelative(difference: Difference | undefined): string {
  if (!difference || difference.relative === null) return "—";

  const signed = difference.relative > 0 ? `+${difference.relative}` : `${difference.relative}`;
  return `${signed}%`;
}

export function formatSeconds(seconds: number | null): string {
  if (seconds === null || seconds === undefined) return "—";
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}min`;
  return `${(seconds / 3600).toFixed(1)}h`;
}

export function isTiming(scope: MetricScopes | TimingScope): scope is TimingScope {
  return "p50_seconds" in scope;
}

// O guardrail que invalida todos os outros números: sem installation_id não há
// como reconstruir a população que o painel afirma estar medindo.
export function hasBlockingDataIssue(guardrails: Guardrails | undefined): boolean {
  if (!guardrails) return false;
  return guardrails.events_missing_installation_id > 0 || guardrails.variant_disagreement > 0;
}

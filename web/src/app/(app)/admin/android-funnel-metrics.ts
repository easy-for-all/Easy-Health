// Types and pure helpers for the "Funil Android Externo" admin block.
//
// Mirrors the payload of GET /api/v1/admin/analytics/android_funnel
// (api/app/services/analytics/android_funnel.rb). Field names stay snake_case
// on purpose so a value can be traced back to the service without a mapping
// table in between.
//
// The unit of every step except `android_users` is one distinct installation.
// A step whose `unit` is "users" is a different population and is rendered as
// such — it is never divided by, or compared against, an installation count.

import { type Metric } from "./android-installations-metrics";

export type { Metric };

export type FunnelPeriod = "since_instrumentation" | "today" | "7d" | "30d";
export type FunnelAudience = "external" | "internal_test" | "all";

export interface FunnelStepRow {
  key: string;
  label: string;
  unit: "installations" | "users";
  count: number;
  conversion_from_previous?: Metric;
  conversion_from_cohort?: Metric;
  note?: string;
}

export interface BiggestDrop {
  from_key: string;
  from_label: string;
  to_key: string;
  to_label: string;
  lost: number;
  drop_rate: Metric;
}

export interface StageBucket {
  key: string;
  label: string;
  count: number;
}

export interface StageDefinition {
  key: string;
  label: string;
  events: string[];
}

export interface AndroidFunnelPayload {
  source: string;
  generated_at: string;
  filters: { period: FunnelPeriod; build: number | null; audience: FunnelAudience };
  definitions: {
    min_instrumented_build: number;
    period: FunnelPeriod;
    window_start: string | null;
    window_end: string | null;
    stage_definitions: StageDefinition[];
    bucket_order: string[];
    instrumentation_note: string;
    unit_note: string;
    anonymous_classification_note: string;
    conflict_note: string;
  };
  cohort: { installations: number; excluded: { missing_or_invalid_build: number } };
  available_builds: number[];
  steps: FunnelStepRow[];
  biggest_drop: BiggestDrop | null;
  stage_buckets: StageBucket[];
  link_failures: Record<string, number>;
}

export interface FunnelInstallationRow {
  installation_id: string;
  created_at: string | null;
  first_seen_at: string | null;
  last_seen_at: string | null;
  app_version: string | null;
  app_build: string | null;
  device_manufacturer: string | null;
  device_model: string | null;
  operating_system: string | null;
  operating_system_version: string | null;
  last_stage: string | null;
  last_stage_label: string | null;
  last_event_name: string | null;
  last_event_at: string | null;
  linked: boolean;
  link_result: string | null;
  last_link_failure_code: string | null;
  link_attempts_count: number | null;
  user_id: number | null;
  email: string | null;
}

export interface FunnelInstallationsPayload {
  stage: string;
  label: string | null;
  total: number;
  page: number;
  per: number;
  installations: FunnelInstallationRow[];
}

export const PERIOD_OPTIONS: { value: FunnelPeriod; label: string }[] = [
  { value: "today", label: "Hoje" },
  { value: "7d", label: "7 dias" },
  { value: "30d", label: "30 dias" },
  { value: "since_instrumentation", label: "Desde a instrumentação" },
];

export const AUDIENCE_OPTIONS: { value: FunnelAudience; label: string }[] = [
  { value: "external", label: "Externos" },
  { value: "internal_test", label: "Internos/teste" },
  { value: "all", label: "Todos" },
];

/**
 * A conversion is only shown when it has a denominator. `no_coverage` means
 * nobody reached the previous step — rendering it as "0%" would read as a total
 * failure instead of an absence of data.
 */
export function formatConversion(metric: Metric | undefined): string {
  if (!metric || metric.denominator === 0 || metric.status === "no_coverage") return "—";
  return `${metric.value.toLocaleString("pt-BR")}%`;
}

/** Build the query string shared by the funnel and its investigation lists. */
export function funnelQuery(filters: {
  period: FunnelPeriod;
  build: string;
  audience: FunnelAudience;
}): string {
  const params = new URLSearchParams({ period: filters.period, audience: filters.audience });
  if (filters.build) params.set("build", filters.build);
  return params.toString();
}

/** Installation ids are UUIDs; the list only needs enough to recognise a row. */
export function shortInstallationId(value: string): string {
  return value.length <= 12 ? value : `${value.slice(0, 8)}…${value.slice(-4)}`;
}

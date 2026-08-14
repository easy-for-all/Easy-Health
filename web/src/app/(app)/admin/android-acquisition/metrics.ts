// Types and pure helpers for the "Aquisição Android" admin section.
//
// TWO UNIVERSES, NEVER MIXED. `ads` is what Google Ads attributed to the
// campaign, on Google's reporting dates. `easyhealth` is what our own database
// recorded, grouped by the local date the Android account was created. The
// backend deliberately exposes no ratio between the two blocks, and neither
// does this file: dividing attributed installs by EasyHealth accounts would be
// a user-level attribution this version does not have.

export type MetricStatus =
  | "complete"
  | "incomplete"
  | "insufficient_sample"
  | "inconsistent"
  | "no_coverage";

export interface Metric {
  value: number;
  numerator: number;
  denominator: number;
  sample_size: number;
  status: MetricStatus;
  cohort_maturity?: string;
  definition: string;
}

// Google Ads ratios are NOT Metric: attributed conversions are decimals with no
// cohort or sample size behind them. null means "no denominator yet".
export interface AdsRatio {
  value: number;
  numerator: number;
  denominator: number;
}

export type SyncStatus = "ok" | "stale" | "error" | "never_synced" | "not_configured";

export interface SyncState {
  status: SyncStatus;
  label: string;
  last_synced_at: string | null;
  last_succeeded_at: string | null;
  last_failed_at: string | null;
  last_error_code: string | null;
  consecutive_failures: number | null;
  campaign_id: string | null;
  missing_configuration: string[];
}

export interface AdsBlock {
  cost_micros: number;
  cost_brl: number;
  impressions: number;
  clicks: number;
  installs: number;
  sign_ups: number;
  cpi_brl: number | null;
  cpa_signup_brl: number | null;
  install_to_signup: AdsRatio | null;
  configured?: boolean;
  days_with_data?: number;
}

export interface ProductBlock {
  accounts: number;
  created_workout: number;
  started_workout: number;
  completed_workout: number;
  cohort_maturity: string;
  account_to_created: Metric;
  created_to_started: Metric;
  started_to_completed: Metric;
  data_quality?: { completed_without_started: number };
}

export interface DailyRow {
  date: string;
  ads: AdsBlock | null;
  easyhealth: ProductBlock;
}

export interface AndroidAcquisition {
  source: string;
  generated_at: string;
  filters: { period: string; start_date: string; end_date: string };
  sync: SyncState;
  ads: AdsBlock;
  easyhealth: ProductBlock;
  daily: DailyRow[];
  definitions: {
    timezone: string;
    cohort_maturity_days: number;
    max_custom_days: number;
    ads_note: string;
    product_note: string;
    comparison_note: string;
    no_cross_rate_note: string;
    cohort_note: string;
    started_note: string;
  };
}

export const PERIOD_OPTIONS = [
  { value: "today", label: "Hoje" },
  { value: "yesterday", label: "Ontem" },
  { value: "7d", label: "7 dias" },
  { value: "30d", label: "30 dias" },
  { value: "custom", label: "Personalizado" },
] as const;

export const DEFAULT_PERIOD = "7d";

export function formatBRL(value: number | null | undefined): string {
  if (value === null || value === undefined) return "—";
  return value.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}

// Attributed conversions can be fractional (data-driven / cross-device
// attribution). Showing "12,00 instalações" for a whole number is noise, and
// rounding 0,83 to 1 would invent a conversion that Google did not attribute.
export function formatConversions(value: number | null | undefined): string {
  if (value === null || value === undefined) return "—";
  if (Number.isInteger(value)) return value.toLocaleString("pt-BR");
  return value.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export function formatCount(value: number | null | undefined): string {
  if (value === null || value === undefined) return "—";
  return value.toLocaleString("pt-BR");
}

// An em dash, never "0%": with no denominator there is no rate, and 0% would
// read as "nobody converted" instead of "nothing to divide by yet".
export function formatMetric(metric: Metric | null | undefined): string {
  if (!metric || metric.status === "no_coverage" || metric.denominator === 0) return "—";
  return `${metric.value.toLocaleString("pt-BR", { maximumFractionDigits: 1 })}%`;
}

export function formatAdsRatio(ratio: AdsRatio | null | undefined): string {
  if (!ratio) return "—";
  return `${ratio.value.toLocaleString("pt-BR", { maximumFractionDigits: 1 })}%`;
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "—";
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Sao_Paulo",
  }).format(new Date(value));
}

export function formatDay(value: string): string {
  const [year, month, day] = value.split("-");
  if (!year || !month || !day) return value;
  return `${day}/${month}`;
}

// Zero attributed sign_ups on a brand-new campaign is a legitimate zero, not a
// broken pipeline. Only a sync that never ran, is not configured or actually
// failed may be presented as a problem.
export function syncTone(status: SyncStatus): "ok" | "warn" | "muted" {
  if (status === "ok") return "ok";
  if (status === "error" || status === "stale") return "warn";
  return "muted";
}

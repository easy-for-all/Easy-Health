// Types and pure helpers for the "App Android" admin section.
//
// The panel's single source for installation counts is AppInstallation on the
// backend (GET /api/v1/admin/analytics/android_installations). Device tokens,
// analytics events and activation_platform are complementary signals rendered
// in their own blocks — none of them is an installation count, and none of them
// is a Google Play download count.

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

export interface VersionRow {
  app_version: string | null;
  app_build: string | null;
  build_number: number | null;
  total_installations: number;
  linked_installations: number;
  anonymous_installations: number;
  active_installations_7d: number;
  link_rate: Metric;
}

export interface ManufacturerRow {
  manufacturer: string | null;
  total_installations: number;
  linked_installations: number;
  active_installations_30d: number;
}

export interface DeviceModelRow {
  manufacturer: string | null;
  device_model: string | null;
  total_installations: number;
  active_installations_30d: number;
}

export interface OsVersionRow {
  operating_system_version: string | null;
  total_installations: number;
}

export interface TimelineRow {
  date: string;
  observed_authenticated_installations: number;
  linked_installations: number;
  link_rate: Metric;
}

export type ComponentStatus = "ok" | "attention" | "critical" | "unknown";

export interface OperationalComponent {
  key: string;
  label: string;
  status: ComponentStatus;
  detail: string;
}

export interface FunnelStep {
  label: string;
  count: number;
  conversion: Metric;
}

export interface AndroidInstallationMetrics {
  source: string;
  generated_at: string;
  definitions: {
    active_7d_since: string;
    active_30d_since: string;
    timeline_days: number;
    healthy_link_rate: number;
    attention_link_rate: number;
    reconciliation_rate: string;
  };
  overview: {
    total_installations: number;
    linked_installations: number;
    anonymous_installations: number;
    authenticated_installations: number;
    unique_linked_users: number;
    users_with_multiple_installations: number;
    active_installations_7d: number;
    active_installations_30d: number;
    new_installations_24h: number;
    new_installations_7d: number;
    new_installations_30d: number;
    link_rate: Metric;
  };
  reconciliation: {
    observed_authenticated_installations: number;
    link_attempted_installations: number;
    linked_installations: number;
    authenticated_unlinked_installations: number;
    conflicts: number;
    failures_by_code: Record<string, number>;
    link_rate: Metric;
  };
  data_quality: {
    linked_without_last_authenticated_at: number;
    authenticated_at_without_user: number;
    linked_without_linked_at: number;
    linked_without_observed_request: number;
    missing_app_build: number;
    invalid_app_build: number;
    missing_app_version: number;
    missing_last_seen_at: number;
  };
  adoption: {
    most_used_version: string | null;
    most_used_version_installations: number;
    most_used_build: number | null;
    most_used_build_installations: number;
    latest_build: number | null;
    latest_build_installations: number;
    latest_build_share: Metric;
  };
  health_timeline: TimelineRow[];
  operational_health: OperationalComponent[];
  installation_provenance: { registered_live: number; backfilled: number; coverage: Metric };
  push: { permission_granted: number; push_enabled: number; valid_fcm_tokens: number };
  analytics_pipeline: {
    android_events_total: number;
    android_events_7d: number;
    installations_with_session: number;
    last_event_at: string | null;
  };
  google_play: {
    configured: boolean;
    official_installs: number | null;
    last_synced_at: string | null;
    source: string | null;
  };
  versions: VersionRow[];
  manufacturers: ManufacturerRow[];
  device_models: DeviceModelRow[];
  operating_system_versions: OsVersionRow[];
  user_funnel: FunnelStep[];
}

export type HealthState = "healthy" | "attention" | "critical" | "no_data";

// The only place the link-rate thresholds exist on the frontend. The backend
// carries the same numbers in `definitions` for its own status derivation.
export const HEALTH_THRESHOLDS = { healthy: 95, attention: 85 } as const;

export const HEALTH_STATE_LABEL: Record<HealthState, string> = {
  healthy: "Saudável",
  attention: "Atenção",
  critical: "Crítico",
  no_data: "Sem dados",
};

/** A rate over an empty sample is "no_data", never a misleading 0% or 100%. */
export function healthState(metric: Metric | undefined): HealthState {
  if (!metric || metric.denominator === 0) return "no_data";
  if (metric.value >= HEALTH_THRESHOLDS.healthy) return "healthy";
  if (metric.value >= HEALTH_THRESHOLDS.attention) return "attention";
  return "critical";
}

/** Percentage for display — an empty sample renders as an em dash, never NaN. */
export function formatRate(metric: Metric | undefined): string {
  if (!metric || metric.denominator === 0) return "—";
  return `${metric.value}%`;
}

/** "100% — 3 de 3 instalações": a rate is never shown without its sample. */
export function formatRateWithSample(metric: Metric | undefined, noun = "instalações"): string {
  if (!metric || metric.denominator === 0) return `sem ${noun} nesta faixa ainda`;
  return `${metric.value}% — ${formatCount(metric.numerator)} de ${formatCount(metric.denominator)} ${noun}`;
}

export function formatCount(value: number | null | undefined): string {
  if (typeof value !== "number" || Number.isNaN(value)) return "—";
  return value.toLocaleString("pt-BR");
}

/** Blank grouping values are only labelled here — the database keeps the NULL. */
export function displayLabel(value: string | number | null | undefined): string {
  if (value === null || value === undefined) return "não informado";
  const text = String(value).trim();
  return text.length > 0 ? text : "não informado";
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "—";
  return parsed.toLocaleDateString("pt-BR", { day: "2-digit", month: "short" });
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "—";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "—";
  return parsed.toLocaleString("pt-BR");
}

export function hasDataQualityIssues(
  dataQuality: AndroidInstallationMetrics["data_quality"] | undefined,
): boolean {
  if (!dataQuality) return false;
  return Object.values(dataQuality).some((count) => count > 0);
}

const STATE_COLOR: Record<HealthState, string> = {
  healthy: "var(--good)",
  attention: "var(--warn)",
  critical: "var(--hot)",
  no_data: "var(--text-dim)",
};

const STATE_BACKGROUND: Record<HealthState, string> = {
  healthy: "var(--good-soft)",
  attention: "var(--warn-soft)",
  critical: "var(--hot-soft)",
  no_data: "var(--surface-2)",
};

export function healthColors(state: HealthState): { color: string; background: string } {
  return { color: STATE_COLOR[state], background: STATE_BACKGROUND[state] };
}

const COMPONENT_STATE: Record<ComponentStatus, HealthState> = {
  ok: "healthy",
  attention: "attention",
  critical: "critical",
  unknown: "no_data",
};

export const COMPONENT_STATUS_LABEL: Record<ComponentStatus, string> = {
  ok: "ok",
  attention: "atenção",
  critical: "crítico",
  unknown: "sem sinal",
};

/** An unknown component is never painted as healthy. */
export function componentColors(status: ComponentStatus): { color: string; background: string } {
  return healthColors(COMPONENT_STATE[status] ?? "no_data");
}

// Mirrors the payload of GET /api/v1/admin/observability
// (api/app/services/observability/dashboard.rb).

export type CheckStatus = "healthy" | "warning" | "critical" | "insufficient_data";

export type CardKey =
  | "api_infrastructure"
  | "android_registration"
  | "android_linkage"
  | "google_auth"
  | "jobs_integrations"
  | "open_incidents";

// Frozen order — the panel renders exactly these six, in this sequence.
export const CARD_ORDER: CardKey[] = [
  "api_infrastructure",
  "android_registration",
  "android_linkage",
  "google_auth",
  "jobs_integrations",
  "open_incidents",
];

export type MetricUnit = "ratio" | "count" | "seconds";

export interface MetricRow {
  check_key: string;
  status: CheckStatus;
  /** null whenever the sample was too small to measure. Never render as 0. */
  value: number | null;
  threshold_value: number | null;
  reference_value: number | null;
  sample_size: number | null;
  dimensions: Record<string, unknown>;
  explanation: string | null;
}

export interface Card {
  key: CardKey;
  title: string;
  status: CheckStatus;
  /** null whenever the sample was too small to measure. Never render as 0. */
  value: number | null;
  unit: MetricUnit;
  headline: string | null;
  sample_size: number | null;
  reference_value: number | null;
  threshold_value: number | null;
  window: { started_at: string | null; ended_at: string | null; label: string | null };
  definition: string | null;
  explanation: string | null;
  updated_at: string | null;
  metrics: MetricRow[];
  incident_ids: number[];
  oldest_opened_at?: string | null;
  last_opened_at?: string | null;
}

export interface Incident {
  id: number;
  source: string;
  check_key: string | null;
  title: string;
  description: string | null;
  severity: "warning" | "critical";
  status: "open" | "acknowledged" | "resolved";
  current_value: number | null;
  threshold_value: number | null;
  dimensions: Record<string, unknown>;
  first_detected_at: string;
  last_detected_at: string;
  acknowledged_at: string | null;
  resolved_at: string | null;
  duration_seconds: number;
  occurrence_count: number;
  notification_count: number;
}

export interface AndroidBuildRow {
  app_version: string | null;
  app_build: string | null;
  build_group: string;
  installations: number;
  authenticated: number;
  linked: number;
  anonymous: number;
  registrations: number;
  google_auth_errors: number;
  /** null below the sample floor. */
  registration_rate: number | null;
  linkage_rate: number | null;
  sample_size: number;
  status: CheckStatus;
}

export interface HeartbeatRow {
  key: string;
  category: string;
  status: CheckStatus;
  expected_interval_seconds: number;
  last_started_at: string | null;
  last_succeeded_at: string | null;
  last_failed_at: string | null;
  last_duration_ms: number | null;
  seconds_since_success: number | null;
  consecutive_failures: number;
  last_error_code: string | null;
}

export interface DataQuality {
  checks_total: number;
  insufficient_data: number;
  last_run_at: string | null;
  stale: boolean;
  notes: string[];
}

export interface ObservabilityPayload {
  generated_at: string;
  range: string;
  overall_status: CheckStatus;
  cards: Record<CardKey, Card>;
  incidents: Incident[];
  android_builds: AndroidBuildRow[];
  heartbeats: HeartbeatRow[];
  thresholds: Record<string, number | boolean>;
  data_quality: DataQuality;
}

export interface TimelineEvent {
  event_name: string;
  occurred_at: string;
  platform: string | null;
  app_version: string | null;
  app_build: string | null;
  result?: string;
  error_code?: string;
  auth_flow?: string;
  link_result?: string;
}

export interface TimelineResponse {
  subject: {
    user_ref: string | null;
    installation_found: boolean;
    installation_linked: boolean;
    platform: string | null;
    app_version: string | null;
    app_build: string | null;
    build_group: string | null;
    first_seen_at: string | null;
    last_seen_at: string | null;
    last_authenticated_at: string | null;
  };
  events: TimelineEvent[];
}

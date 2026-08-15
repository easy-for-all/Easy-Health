// Types and pure helpers for the "Eventos & Comunicações" admin section.
//
// TWO THINGS THAT LOOK ALIKE AND ARE NOT. `candidate_channels` counts events
// ELIGIBLE for a channel — an event routed to push+email counts on both, even
// if Make chose to send neither. `push_dispatch_results` counts what was
// actually requested and what the provider did with it. Labelling a candidate
// as "enviado" would report intent as delivery, so this file keeps the wording
// apart and the page renders them as separate blocks.

export interface Rate {
  numerator: number;
  denominator: number;
  value: number | null;
}

export interface Summary {
  events_generated: number;
  sent_to_make: number;
  accepted_by_make: number;
  failed_make: number;
  unique_users: number;
  push_requested: number;
  provider_accepted: number;
  provider_rejected: number;
  push_deferred: number;
  push_skipped: number;
  rates: {
    generated_to_sent: Rate;
    sent_to_accepted: Rate;
    dispatch_to_provider_accepted: Rate;
  };
}

export interface EventRow {
  event_name: string;
  candidate_channels: string[];
  generated: number;
  sent_to_make: number;
  accepted_by_make: number;
  failed_make: number;
  disabled: number;
  push_requested: number;
  provider_accepted: number;
  provider_rejected: number;
  push_deferred: number;
  push_skipped: number;
  unique_users: number;
  last_generated_at: string | null;
  last_sent_to_make_at: string | null;
}

export interface ChannelRow {
  channel: string;
  candidate_events: number;
  sent_to_make: number;
  unique_users: number;
  configured: boolean;
}

export interface OriginRow {
  origin_surface: string;
  events: number;
  unique_users: number;
}

export interface SkipRow {
  skip_reason: string;
  count: number;
}

export interface DeferredRow {
  defer_reason: string;
  count: number;
}

export interface PushDispatchResults {
  requested: number;
  provider_accepted: number;
  provider_rejected: number;
  deferred: number;
  skipped: number;
  not_correlated: number;
  deferred_reasons: DeferredRow[];
  skips: SkipRow[];
  defer_reasons: string[];
}

export type SchedulerStatus = "healthy" | "warning" | "critical" | "insufficient_data";

export interface SchedulerRow {
  key: string;
  registered: boolean;
  status: SchedulerStatus;
  expected_interval_seconds?: number;
  last_run_at?: string | null;
  last_success_at?: string | null;
  last_failure_at?: string | null;
  next_expected_at?: string | null;
  last_error_code?: string | null;
  consecutive_failures?: number;
  duration_ms?: number | null;
  candidates_found?: number | null;
  events_created?: number | null;
}

export interface RecentEvent {
  event_id: number;
  event_name: string;
  user_id: number;
  origin_surface: string;
  candidate_channels: string[];
  created_at: string | null;
  make_status: string;
  make_http_status: number | null;
  make_execution_id: string | null;
  make_error: string | null;
  push_dispatch_id: number | null;
  push_status: string | null;
  skip_reason: string | null;
  defer_reason: string | null;
  next_allowed_at: string | null;
  correlation_id: string | null;
}

export interface Warning {
  code: string;
  severity: "critical" | "warning";
  message: string;
}

export interface EventOrchestration {
  period: { key: string; from: string; to: string };
  summary: Summary;
  by_event: EventRow[];
  candidate_channels: ChannelRow[];
  push_dispatch_results: PushDispatchResults;
  by_origin: OriginRow[];
  schedulers: SchedulerRow[];
  recent_events: RecentEvent[];
  warnings: Warning[];
  catalog: { orchestration_events: string[]; push_events: string[] };
}

export const DEFAULT_PERIOD = "24h";

export const PERIOD_OPTIONS = [
  { value: "24h", label: "24 horas" },
  { value: "7d", label: "7 dias" },
  { value: "30d", label: "30 dias" },
  { value: "custom", label: "Personalizado" },
];

const SCHEDULER_LABELS: Record<string, string> = {
  first_workout_not_started_2h: "Lembrete 2h",
  first_workout_not_started_24h: "Lembrete 24h",
  scheduled_workout_reminder: "Horário preferido",
  relationship_daily_job: "Jornada diária",
  make_pending_retry: "Retry Make",
  push_dispatch_deferred: "Push deferido",
};

const ORIGIN_LABELS: Record<string, string> = {
  android: "Android",
  web: "Web",
  backend_scheduler: "Scheduler",
  admin: "Admin",
  unknown: "Desconhecida",
};

const CHANNEL_LABELS: Record<string, string> = {
  push: "Push",
  email: "E-mail",
  whatsapp: "WhatsApp",
  in_app: "In-app",
};

export function schedulerLabel(key: string): string {
  return SCHEDULER_LABELS[key] ?? key;
}

export function originLabel(surface: string): string {
  return ORIGIN_LABELS[surface] ?? surface;
}

export function channelLabel(channel: string): string {
  return CHANNEL_LABELS[channel] ?? channel;
}

export function formatCount(value: number | null | undefined): string {
  if (value === null || value === undefined) return "—";
  return new Intl.NumberFormat("pt-BR").format(value);
}

// A rate with no denominator is "—", never "0%": zero of zero is the absence of
// a measurement, and rendering it as 0% invents a failure that did not happen.
export function formatRate(rate: Rate | null | undefined): string {
  if (!rate || rate.value === null || rate.denominator === 0) return "—";
  return `${(rate.value * 100).toFixed(1)}%`;
}

export function formatRateDetail(rate: Rate | null | undefined): string {
  if (!rate) return "—";
  return `${formatCount(rate.numerator)} de ${formatCount(rate.denominator)}`;
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "nunca";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

export function formatInterval(seconds: number | null | undefined): string {
  if (!seconds) return "—";
  if (seconds < 3600) return `${Math.round(seconds / 60)}min`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)}h`;
  return `${Math.round(seconds / 86400)}d`;
}

export type Tone = "ok" | "warn" | "bad" | "muted";

export function schedulerTone(row: SchedulerRow): Tone {
  if (!row.registered) return "warn";
  if (row.status === "critical") return "bad";
  if (row.status === "warning") return "warn";
  if (row.status === "insufficient_data") return "muted";
  return "ok";
}

export function schedulerStatusLabel(row: SchedulerRow): string {
  if (!row.registered) return "sem registro";
  const labels: Record<SchedulerStatus, string> = {
    healthy: "saudável",
    warning: "atrasado",
    critical: "parado",
    insufficient_data: "aguardando",
  };
  return labels[row.status] ?? row.status;
}

export function warningTone(severity: Warning["severity"]): Tone {
  return severity === "critical" ? "bad" : "warn";
}

// Make status as an operator reads it. "dead_letter" in particular must not
// look like a retry still in flight — it is a permanent contract failure.
const MAKE_STATUS_LABELS: Record<string, string> = {
  pending: "na fila",
  sending: "enviando",
  accepted_by_make: "aceito",
  retrying: "repetindo",
  failed_to_reach_make: "falhou",
  dead_letter: "descartado",
  disabled: "não enviado",
  skipped: "ignorado",
};

export function makeStatusLabel(status: string | null | undefined): string {
  if (!status) return "—";
  return MAKE_STATUS_LABELS[status] ?? status;
}

export function makeStatusTone(status: string | null | undefined): Tone {
  if (status === "accepted_by_make") return "ok";
  if (status === "dead_letter" || status === "failed_to_reach_make") return "bad";
  if (status === "retrying" || status === "disabled") return "warn";
  return "muted";
}

const PUSH_STATUS_LABELS: Record<string, string> = {
  received: "recebido",
  processing: "processando",
  provider_accepted: "aceito",
  partially_accepted: "parcial",
  opened: "aberto",
  failed: "rejeitado",
  deferred: "deferido",
  skipped: "ignorado",
};

export function pushStatusLabel(status: string | null | undefined): string {
  if (!status) return "—";
  return PUSH_STATUS_LABELS[status] ?? status;
}

export function pushStatusTone(status: string | null | undefined): Tone {
  if (!status) return "muted";
  if (["provider_accepted", "partially_accepted", "opened"].includes(status)) return "ok";
  if (status === "failed") return "bad";
  if (status === "deferred") return "warn";
  if (status === "skipped") return "warn";
  return "muted";
}

export function isDeferReason(reason: string, deferReasons: string[]): boolean {
  return deferReasons.includes(reason);
}

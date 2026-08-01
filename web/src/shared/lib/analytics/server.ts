import * as Sentry from "@sentry/nextjs";
import { getAnalyticsContext } from "./context";
import { EventName, SERVER_TRACKED_EVENTS } from "./taxonomy";

// Sends auditable events to the backend (POST /api/v1/analytics/events).
// Batched and non-blocking: analytics must never break the main experience.

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";
const ENDPOINT = "/api/v1/analytics/events";

// Mirrors shared/lib/api.ts: omit any header whose value is not available yet
// rather than sending "undefined" and minting a junk dimension value.
function correlationHeaders(): Record<string, string> {
  try {
    const context = getAnalyticsContext();
    const headers: Record<string, string> = {};

    if (context.installation_id) headers["X-Installation-Id"] = context.installation_id;
    if (context.platform) headers["X-Platform"] = context.platform;
    if (context.app_version) headers["X-App-Version"] = context.app_version;
    if (context.build_number) headers["X-App-Build"] = context.build_number;
    if (context.session_id) headers["X-Session-Id"] = context.session_id;

    return headers;
  } catch {
    return {};
  }
}

const MAX_BATCH = 20;
const MAX_QUEUE = 100; // hard cap so a broken network can't grow memory unbounded
const FLUSH_DELAY_MS = 3000;
const EVENT_TTL_MS = 6 * 60 * 60 * 1000; // 6h — stale events are dropped

interface QueuedEvent {
  event_name: string;
  event_version: number;
  occurred_at: string;
  session_id: string;
  anonymous_id: string;
  platform: string;
  app_surface: string;
  app_version?: string;
  build_number?: string;
  environment: string;
  locale?: string;
  timezone?: string;
  source?: string;
  properties: Record<string, unknown>;
  idempotency_key: string;
  _queued_at: number;
}

let queue: QueuedEvent[] = [];
let flushTimer: ReturnType<typeof setTimeout> | null = null;

const SERVER_SET = new Set<string>(SERVER_TRACKED_EVENTS as string[]);

export function isServerEvent(name: string): boolean {
  return SERVER_SET.has(name);
}

function buildEvent(
  name: EventName,
  version: number,
  properties: Record<string, unknown>
): QueuedEvent {
  const ctx = getAnalyticsContext();
  return {
    event_name: name,
    event_version: version,
    occurred_at: new Date().toISOString(),
    session_id: ctx.session_id,
    anonymous_id: ctx.anonymous_id,
    platform: ctx.platform,
    app_surface: ctx.app_surface,
    app_version: ctx.app_version,
    build_number: ctx.build_number,
    environment: ctx.environment,
    locale: ctx.locale,
    timezone: ctx.timezone,
    source: "web_client",
    // installation_id rides inside properties on purpose: no column, no
    // migration, and it is the ONLY way an anonymous pre-auth event can be
    // joined back to an app_installations row. The X-Installation-Id header is
    // not enough — sendBeacon (the background/close flush) carries no headers.
    // It never replaces anonymous_id and is never a user identifier.
    properties: ctx.installation_id
      ? { ...(properties ?? {}), installation_id: ctx.installation_id }
      : (properties ?? {}),
    idempotency_key:
      typeof crypto !== "undefined" && crypto.randomUUID
        ? crypto.randomUUID()
        : `${name}-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    _queued_at: Date.now(),
  };
}

export function enqueueServerEvent(
  name: EventName,
  version: number,
  properties: Record<string, unknown> = {}
): void {
  if (typeof window === "undefined") return;
  if (!isServerEvent(name)) return; // only server-sink events go to the backend
  queue.push(buildEvent(name, version, properties));
  if (queue.length > MAX_QUEUE) queue = queue.slice(-MAX_QUEUE);
  scheduleFlush();
}

function scheduleFlush(): void {
  if (flushTimer) return;
  flushTimer = setTimeout(() => {
    flushTimer = null;
    void flush();
  }, FLUSH_DELAY_MS);
}

function strip(event: QueuedEvent): Omit<QueuedEvent, "_queued_at"> {
  const { _queued_at, ...rest } = event;
  void _queued_at;
  return rest;
}

export async function flush(useBeacon = false): Promise<void> {
  if (typeof window === "undefined" || queue.length === 0) return;

  const now = Date.now();
  queue = queue.filter((e) => now - e._queued_at < EVENT_TTL_MS);
  if (queue.length === 0) return;

  const batch = queue.slice(0, MAX_BATCH);
  const payload = JSON.stringify({ events: batch.map(strip) });

  try {
    if (useBeacon && navigator.sendBeacon) {
      const ok = navigator.sendBeacon(
        `${API_URL}${ENDPOINT}`,
        new Blob([payload], { type: "application/json" })
      );
      if (ok) queue = queue.slice(batch.length);
      return;
    }

    const res = await fetch(`${API_URL}${ENDPOINT}`, {
      method: "POST",
      credentials: "include",
      // This sender bypasses shared/lib/api.ts, so the correlation headers have
      // to be added here too — otherwise ingestion requests are the only
      // traffic the backend cannot attribute to a platform or build.
      // sendBeacon above cannot carry custom headers; those events still carry
      // the same dimensions inside the body.
      headers: { "Content-Type": "application/json", ...correlationHeaders() },
      body: payload,
      keepalive: true,
    });
    if (res.ok) {
      queue = queue.slice(batch.length);
      if (queue.length > 0) scheduleFlush(); // drain the rest
    }
  } catch {
    // Keep the batch queued for the next attempt; never throw to the caller.
    // Leave a breadcrumb so a systemic ingestion outage is visible in Sentry
    // without turning analytics failures into user-facing errors.
    try {
      Sentry.addBreadcrumb({
        category: "analytics",
        level: "warning",
        message: "analytics flush failed",
        data: { queued: queue.length },
      });
    } catch {
      /* Sentry not initialized — ignore */
    }
  }
}

// Flush synchronously when the app is backgrounded/closed.
export function flushOnBackground(): void {
  void flush(true);
}

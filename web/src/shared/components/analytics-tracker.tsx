"use client";

import { useEffect } from "react";
import { trackEvent, trackConversion, trackServerEvent } from "@/shared/lib/analytics";
import type { EventName } from "@/shared/lib/analytics/taxonomy";

interface Props {
  eventName: string;
  params?: Record<string, string | number | boolean>;
  conversionLabel?: string;
  // Optional taxonomy-aligned server event to persist alongside the GA4 event,
  // for cases where the GA4 event name differs from the auditable taxonomy name
  // (e.g. GA4 "subscription_created" ⇒ server "subscription_started").
  serverEvent?: EventName;
}

export function AnalyticsTracker({ eventName, params, conversionLabel, serverEvent }: Props) {
  useEffect(() => {
    trackEvent(eventName, params);
    if (conversionLabel) trackConversion(conversionLabel);
    if (serverEvent) trackServerEvent(serverEvent, params ?? {});
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return null;
}

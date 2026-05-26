"use client";

import { useEffect } from "react";
import { trackEvent } from "@/shared/lib/analytics";

interface Props {
  eventName: string;
  params?: Record<string, string | number | boolean>;
}

export function AnalyticsTracker({ eventName, params }: Props) {
  useEffect(() => {
    trackEvent(eventName, params);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return null;
}

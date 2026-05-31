"use client";

import { useEffect } from "react";
import { trackEvent, trackConversion } from "@/shared/lib/analytics";

interface Props {
  eventName: string;
  params?: Record<string, string | number | boolean>;
  conversionLabel?: string;
}

export function AnalyticsTracker({ eventName, params, conversionLabel }: Props) {
  useEffect(() => {
    trackEvent(eventName, params);
    if (conversionLabel) trackConversion(conversionLabel);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return null;
}

"use client";

import { useEffect } from "react";
import { initAnalytics } from "@/shared/lib/analytics/init";

// Boots the central analytics service once on the client: consent-aware, sets
// up native lifecycle listeners and the background flush. Renders nothing.
export function AnalyticsBoot() {
  useEffect(() => {
    initAnalytics();
  }, []);
  return null;
}

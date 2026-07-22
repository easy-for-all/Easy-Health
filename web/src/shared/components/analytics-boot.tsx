"use client";

import { useEffect } from "react";
import { initAnalytics } from "@/shared/lib/analytics/init";
import { useScreenTracking } from "@/shared/lib/analytics/screen";

// Boots the central analytics service once on the client: consent-aware, sets
// up native lifecycle listeners and the background flush. Also tracks screen_view
// on real navigations (deduped). Renders nothing.
export function AnalyticsBoot() {
  useEffect(() => {
    initAnalytics();
  }, []);
  useScreenTracking();
  return null;
}

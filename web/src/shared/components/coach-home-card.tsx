"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import type { CoachRecommendation } from "@/shared/types/coach-recommendation";
import { CoachRecommendationCard } from "./coach-recommendation-card";
import { CoachInsightsSection } from "./coach-insights-section";

export function CoachHomeCard() {
  const [loading, setLoading] = useState(true);
  const [hasPending, setHasPending] = useState(false);

  const fetchRecommendation = useCallback(async () => {
    try {
      const data = await api.get<{ recommendation: CoachRecommendation | null }>(
        "/api/v1/coach/recommendations/current"
      );
      setHasPending(data?.recommendation?.status === "pending");
    } catch {
      setHasPending(false);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchRecommendation();
  }, [fetchRecommendation]);

  if (loading) return null;

  if (hasPending) {
    return <CoachRecommendationCard onResolved={fetchRecommendation} />;
  }

  return <CoachInsightsSection />;
}

"use client";

import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import type { CoachInsight } from "@/shared/types/coach-insight";

const SEVERITY_STYLES: Record<string, { bg: string; border: string; icon: string; color: string }> = {
  info:    { bg: "var(--primary-soft)",  border: "var(--primary-border, var(--border))", icon: "💡", color: "var(--primary)" },
  warning: { bg: "var(--warning-soft, #fff7e6)",  border: "#fbbf24", icon: "⚠️", color: "#d97706" },
  success: { bg: "var(--success-soft, #f0fdf4)", border: "#86efac", icon: "🎉", color: "#16a34a" },
};

export function CoachInsightsSection() {
  const [insights, setInsights] = useState<CoachInsight[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.get<CoachInsight[]>("/api/v1/coach/insights")
      .then((data) => setInsights(data ?? []))
      .catch(() => setInsights([]))
      .finally(() => setLoading(false));
  }, []);

  async function handleRead(id: number) {
    try {
      await api.post(`/api/v1/coach/insights/${id}/read`, {});
      setInsights((prev) => prev.filter((i) => i.id !== id));
    } catch {
      // ignore
    }
  }

  if (loading || insights.length === 0) return null;

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <p style={{ fontSize: 12, fontWeight: 700, color: "var(--text-dim)", textTransform: "uppercase", letterSpacing: "0.06em", margin: 0 }}>
        Seu Coach aprendeu sobre você
      </p>
      {insights.slice(0, 3).map((insight) => {
        const style = SEVERITY_STYLES[insight.severity] ?? SEVERITY_STYLES.info;
        return (
          <div
            key={insight.id}
            style={{
              background: style.bg,
              border: `1px solid ${style.border}`,
              borderRadius: "var(--r-lg)",
              padding: "14px 16px",
              display: "flex",
              gap: 12,
              alignItems: "flex-start",
            }}
          >
            <span style={{ fontSize: 20, flexShrink: 0, marginTop: 1 }}>{style.icon}</span>
            <div style={{ flex: 1 }}>
              <p style={{ fontSize: 13, fontWeight: 700, color: style.color, margin: "0 0 4px" }}>
                {insight.title}
              </p>
              <p style={{ fontSize: 13, color: "var(--text)", margin: 0, lineHeight: 1.5 }}>
                {insight.message}
              </p>
            </div>
            <button
              onClick={() => handleRead(insight.id)}
              aria-label="Marcar como lido"
              style={{
                background: "none",
                border: "none",
                cursor: "pointer",
                color: "var(--text-dim)",
                fontSize: 16,
                padding: "2px 4px",
                flexShrink: 0,
              }}
            >
              ×
            </button>
          </div>
        );
      })}
    </div>
  );
}

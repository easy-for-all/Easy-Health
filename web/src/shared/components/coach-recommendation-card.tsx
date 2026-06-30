"use client";

import { useEffect, useRef, useState } from "react";
import { api } from "@/shared/lib/api";
import type { CoachRecommendation } from "@/shared/types/coach-recommendation";

type CardStatus = "loading" | "idle" | "pending" | "accepting" | "accepted" | "dismissing" | "dismissed";

interface Props {
  onResolved?: () => void;
}

export function CoachRecommendationCard({ onResolved }: Props = {}) {
  const [recommendation, setRecommendation] = useState<CoachRecommendation | null>(null);
  const [status, setStatus] = useState<CardStatus>("loading");
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (status === "idle") {
      onResolved?.();
    }
  }, [status]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    api
      .get<{ recommendation: CoachRecommendation | null }>("/api/v1/coach/recommendations/current")
      .then((data) => {
        setRecommendation(data?.recommendation ?? null);
        setStatus(data?.recommendation ? "pending" : "idle");
      })
      .catch(() => setStatus("idle"));

    return () => {
      if (hideTimer.current) clearTimeout(hideTimer.current);
    };
  }, []);

  async function handleAccept() {
    if (!recommendation) return;
    setStatus("accepting");
    try {
      const data = await api.post<{ recommendation: CoachRecommendation }>(`/api/v1/coach/recommendations/${recommendation.id}/accept`, {});
      setRecommendation(data.recommendation);
      setStatus("accepted");
      hideTimer.current = setTimeout(() => setStatus("idle"), 3000);
    } catch {
      setStatus("pending");
    }
  }

  async function handleDismiss() {
    if (!recommendation) return;
    setStatus("dismissing");
    try {
      await api.post(`/api/v1/coach/recommendations/${recommendation.id}/dismiss`, {});
      setStatus("dismissed");
      hideTimer.current = setTimeout(() => setStatus("idle"), 1500);
    } catch {
      setStatus("pending");
    }
  }

  if (status === "loading" || status === "idle" || status === "dismissed") return null;

  const isActing = status === "accepting" || status === "dismissing";
  const rec = recommendation!;

  if (status === "accepted") {
    return (
      <div
        style={{
          background: "var(--success-soft, #f0fdf4)",
          border: "1px solid #86efac",
          borderRadius: "var(--r-lg)",
          padding: "14px 16px",
          display: "flex",
          alignItems: "center",
          gap: 10,
        }}
      >
        <span style={{ fontSize: 20 }}>✅</span>
        <p style={{ fontSize: 13, color: "#16a34a", margin: 0, fontWeight: 600 }}>
          Carga atualizada para {formatWeight(rec.recommended_value)} em {rec.exercise?.name ?? rec.title}
        </p>
      </div>
    );
  }

  return (
    <div
      style={{
        background: "var(--primary-soft)",
        border: "1px solid var(--primary-border, var(--border))",
        borderRadius: "var(--r-lg)",
        padding: "14px 16px",
        display: "flex",
        flexDirection: "column",
        gap: 12,
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <p style={{ fontSize: 12, fontWeight: 700, color: "var(--text-dim)", textTransform: "uppercase", letterSpacing: "0.06em", margin: 0 }}>
          Coach EasyHealth
        </p>
        <span
          style={{
            fontSize: 10,
            fontWeight: 700,
            background: "var(--primary)",
            color: "#fff",
            borderRadius: 4,
            padding: "2px 6px",
            letterSpacing: "0.04em",
          }}
        >
          IA
        </span>
      </div>

      {/* Exercise name */}
      {rec.exercise && (
        <p style={{ fontSize: 15, fontWeight: 700, color: "var(--text)", margin: 0 }}>
          {rec.exercise.name}
        </p>
      )}

      {/* Weight progression */}
      {rec.current_value != null && rec.recommended_value != null && (
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <div style={{ textAlign: "center" }}>
            <p style={{ fontSize: 11, color: "var(--text-dim)", margin: "0 0 2px", fontWeight: 600 }}>ATUAL</p>
            <p style={{ fontSize: 22, fontWeight: 800, color: "var(--text)", margin: 0 }}>
              {formatWeight(rec.current_value)}
            </p>
          </div>
          <span style={{ fontSize: 20, color: "var(--primary)", fontWeight: 700 }}>→</span>
          <div style={{ textAlign: "center" }}>
            <p style={{ fontSize: 11, color: "var(--primary)", margin: "0 0 2px", fontWeight: 600 }}>SUGERIDO</p>
            <p style={{ fontSize: 22, fontWeight: 800, color: "var(--primary)", margin: 0 }}>
              {formatWeight(rec.recommended_value)}
            </p>
          </div>
        </div>
      )}

      {/* Reasons */}
      {rec.reasons.length > 0 && (
        <ul style={{ margin: 0, padding: "0 0 0 16px", display: "flex", flexDirection: "column", gap: 4 }}>
          {rec.reasons.slice(0, 2).map((reason, i) => (
            <li key={i} style={{ fontSize: 12, color: "var(--text-dim)", lineHeight: 1.4 }}>
              {reason}
            </li>
          ))}
        </ul>
      )}

      {/* Actions */}
      <div style={{ display: "flex", gap: 8, marginTop: 2 }}>
        <button
          onClick={handleDismiss}
          disabled={isActing}
          style={{
            flex: 1,
            padding: "8px 0",
            borderRadius: "var(--r-md)",
            border: "1px solid var(--border)",
            background: "transparent",
            color: "var(--text-dim)",
            fontSize: 13,
            fontWeight: 600,
            cursor: isActing ? "not-allowed" : "pointer",
            opacity: isActing ? 0.6 : 1,
          }}
        >
          {status === "dismissing" ? "Ignorando…" : "Ignorar"}
        </button>
        <button
          onClick={handleAccept}
          disabled={isActing}
          style={{
            flex: 2,
            padding: "8px 0",
            borderRadius: "var(--r-md)",
            border: "none",
            background: "var(--primary)",
            color: "#fff",
            fontSize: 13,
            fontWeight: 700,
            cursor: isActing ? "not-allowed" : "pointer",
            opacity: isActing ? 0.6 : 1,
          }}
        >
          {status === "accepting" ? "Aplicando…" : "Aceitar →"}
        </button>
      </div>
    </div>
  );
}

function formatWeight(value: number | null): string {
  if (value == null) return "—";
  return Number.isInteger(value) ? `${value}kg` : `${value}kg`;
}

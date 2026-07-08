"use client";

import { forwardRef } from "react";
import { getMotivationalPhrase } from "./motivational-phrase";
import { MUSCLE_LABELS } from "@/shared/utils/muscle-labels";

type ShareCardProps = {
  workoutName: string;
  durationMinutes: number;
  volumeKg: number;
  exerciseCount: number;
  muscles: string[];
  hasPR?: boolean;
  caloriesEstimated?: number;
};

export const ShareCard = forwardRef<HTMLDivElement, ShareCardProps>(
  ({ workoutName, durationMinutes, volumeKg, exerciseCount, muscles, hasPR, caloriesEstimated }, ref) => {
    const phrase = getMotivationalPhrase(volumeKg);
    const volumeDisplay = volumeKg >= 1000
      ? `${(volumeKg / 1000).toFixed(1)}t`
      : `${volumeKg}kg`;
    const showCalories = caloriesEstimated != null && caloriesEstimated > 0;
    const cols = showCalories ? "grid-cols-2" : "grid-cols-3";

    const gridCols = showCalories
      ? { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }
      : { display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 };

    return (
      <div
        ref={ref}
        style={{
          position: "relative",
          width: 360,
          overflow: "hidden",
          borderRadius: 24,
          background: "linear-gradient(135deg, #030712 0%, #111827 50%, #0c0a1e 100%)",
          padding: 24,
          color: "#fff",
          fontFamily: "Arial, Helvetica, sans-serif",
          boxSizing: "border-box",
        }}
      >
        {/* Background glow */}
        <div style={{
          position: "absolute",
          inset: 0,
          opacity: 0.2,
          background: "radial-gradient(ellipse at 30% 20%, rgba(59,130,246,0.5) 0%, transparent 60%)",
          pointerEvents: "none",
        }} />

        {/* Header */}
        <div style={{ position: "relative", marginBottom: 20, display: "flex", alignItems: "flex-start", justifyContent: "space-between" }}>
          <div>
            <p style={{ fontSize: 10, fontWeight: 700, textTransform: "uppercase", letterSpacing: 4, color: "#818cf8", margin: 0 }}>EasyHealth</p>
            <h2 style={{ marginTop: 4, fontSize: 20, fontWeight: 700, color: "#fff", margin: "4px 0 0" }}>{workoutName}</h2>
          </div>
          {hasPR && (
            <span style={{ borderRadius: 999, background: "rgba(250,204,21,0.2)", border: "1px solid rgba(250,204,21,0.4)", padding: "4px 10px", fontSize: 11, fontWeight: 700, color: "#fbbf24" }}>
              🏆 PR
            </span>
          )}
        </div>

        {/* Metrics grid */}
        <div style={{ position: "relative", marginBottom: 20, ...gridCols }}>
          {[
            { value: String(durationMinutes), label: "min" },
            { value: volumeDisplay, label: "volume", color: "#a5b4fc" },
            { value: String(exerciseCount), label: "exercícios" },
          ].map(({ value, label, color }) => (
            <div key={label} style={{ borderRadius: 16, padding: 12, textAlign: "center", background: "rgba(255,255,255,0.10)" }}>
              <p style={{ fontSize: 22, fontWeight: 700, color: color ?? "#fff", margin: 0 }}>{value}</p>
              <p style={{ fontSize: 11, color: "rgba(255,255,255,0.60)", margin: "2px 0 0" }}>{label}</p>
            </div>
          ))}
          {showCalories && (
            <div style={{ borderRadius: 16, padding: 12, textAlign: "center", background: "rgba(255,165,0,0.15)" }}>
              <p style={{ fontSize: 22, fontWeight: 700, color: "#fdba74", margin: 0 }}>~{caloriesEstimated}</p>
              <p style={{ fontSize: 11, color: "rgba(255,255,255,0.60)", margin: "2px 0 0" }}>kcal</p>
            </div>
          )}
        </div>

        {/* Muscle badges */}
        {muscles.length > 0 && (
          <div style={{ position: "relative", marginBottom: 20, display: "flex", flexWrap: "wrap", gap: 6 }}>
            {muscles.slice(0, 4).map((m) => (
              <span key={m} style={{ borderRadius: 999, padding: "4px 10px", fontSize: 11, fontWeight: 500, color: "#a5b4fc", background: "rgba(99,102,241,0.20)", border: "1px solid rgba(99,102,241,0.30)" }}>
                {MUSCLE_LABELS[m] ?? m}
              </span>
            ))}
          </div>
        )}

        {/* Phrase */}
        <div style={{ position: "relative", paddingTop: 16, borderTop: "1px solid rgba(255,255,255,0.10)" }}>
          <p style={{ fontSize: 13, fontStyle: "italic", color: "rgba(255,255,255,0.70)", margin: 0 }}>&ldquo;{phrase}&rdquo;</p>
        </div>
      </div>
    );
  }
);

ShareCard.displayName = "ShareCard";

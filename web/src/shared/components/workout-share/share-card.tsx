"use client";

import { forwardRef } from "react";
import { getMotivationalPhrase } from "./motivational-phrase";

type ShareCardProps = {
  workoutName: string;
  durationMinutes: number;
  volumeKg: number;
  exerciseCount: number;
  muscles: string[];
  hasPR?: boolean;
  caloriesEstimated?: number;
};

const MUSCLE_LABELS: Record<string, string> = {
  chest: "Peito", back: "Costas", shoulders: "Ombros",
  biceps: "Bíceps", triceps: "Tríceps", legs: "Pernas", core: "Core",
};

export const ShareCard = forwardRef<HTMLDivElement, ShareCardProps>(
  ({ workoutName, durationMinutes, volumeKg, exerciseCount, muscles, hasPR, caloriesEstimated }, ref) => {
    const phrase = getMotivationalPhrase(volumeKg);
    const volumeDisplay = volumeKg >= 1000
      ? `${(volumeKg / 1000).toFixed(1)}t`
      : `${volumeKg}kg`;
    const showCalories = caloriesEstimated != null && caloriesEstimated > 0;
    const cols = showCalories ? "grid-cols-2" : "grid-cols-3";

    return (
      <div
        ref={ref}
        className="relative w-[360px] overflow-hidden rounded-3xl bg-gradient-to-br from-gray-950 via-gray-900 to-primary-950 p-6 text-white"
        style={{ fontFamily: "Arial, sans-serif" }}
      >
        {/* Background glow */}
        <div className="absolute inset-0 opacity-20" style={{
          background: "radial-gradient(ellipse at 30% 20%, rgba(59,130,246,0.5) 0%, transparent 60%)",
        }} />

        {/* Header */}
        <div className="relative mb-5 flex items-start justify-between">
          <div>
            <p className="text-xs font-bold uppercase tracking-widest text-primary-400">EasyHealth</p>
            <h2 className="mt-1 text-xl font-bold text-white">{workoutName}</h2>
          </div>
          {hasPR && (
            <span className="rounded-full bg-yellow-400/20 border border-yellow-400/40 px-2.5 py-1 text-xs font-bold text-yellow-400">
              🏆 PR
            </span>
          )}
        </div>

        {/* Metrics grid */}
        <div className={`relative mb-5 grid ${cols} gap-3`}>
          <div className="rounded-2xl p-3 text-center" style={{ background: "rgba(255,255,255,0.10)" }}>
            <p className="text-2xl font-bold text-white">{durationMinutes}</p>
            <p className="text-xs" style={{ color: "rgba(255,255,255,0.60)" }}>min</p>
          </div>
          <div className="rounded-2xl p-3 text-center" style={{ background: "rgba(255,255,255,0.10)" }}>
            <p className="text-2xl font-bold text-primary-300">{volumeDisplay}</p>
            <p className="text-xs" style={{ color: "rgba(255,255,255,0.60)" }}>volume</p>
          </div>
          <div className="rounded-2xl p-3 text-center" style={{ background: "rgba(255,255,255,0.10)" }}>
            <p className="text-2xl font-bold text-white">{exerciseCount}</p>
            <p className="text-xs" style={{ color: "rgba(255,255,255,0.60)" }}>exercícios</p>
          </div>
          {showCalories && (
            <div className="rounded-2xl p-3 text-center" style={{ background: "rgba(255,165,0,0.15)" }}>
              <p className="text-2xl font-bold text-orange-300">~{caloriesEstimated}</p>
              <p className="text-xs" style={{ color: "rgba(255,255,255,0.60)" }}>kcal</p>
            </div>
          )}
        </div>

        {/* Muscle badges */}
        {muscles.length > 0 && (
          <div className="relative mb-5 flex flex-wrap gap-1.5">
            {muscles.slice(0, 4).map((m) => (
              <span key={m} className="rounded-full px-2.5 py-1 text-xs font-medium text-primary-300" style={{ background: "rgba(99,102,241,0.20)", border: "1px solid rgba(99,102,241,0.30)" }}>
                {MUSCLE_LABELS[m] ?? m}
              </span>
            ))}
          </div>
        )}

        {/* Phrase */}
        <div className="relative pt-4" style={{ borderTop: "1px solid rgba(255,255,255,0.10)" }}>
          <p className="text-sm italic" style={{ color: "rgba(255,255,255,0.70)" }}>&ldquo;{phrase}&rdquo;</p>
        </div>
      </div>
    );
  }
);

ShareCard.displayName = "ShareCard";

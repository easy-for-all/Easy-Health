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
};

const MUSCLE_LABELS: Record<string, string> = {
  chest: "Peito", back: "Costas", shoulders: "Ombros",
  biceps: "Bíceps", triceps: "Tríceps", legs: "Pernas", core: "Core",
};

export const ShareCard = forwardRef<HTMLDivElement, ShareCardProps>(
  ({ workoutName, durationMinutes, volumeKg, exerciseCount, muscles, hasPR }, ref) => {
    const phrase = getMotivationalPhrase(volumeKg);
    const volumeDisplay = volumeKg >= 1000
      ? `${(volumeKg / 1000).toFixed(1)}t`
      : `${volumeKg}kg`;

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
        <div className="relative mb-5 grid grid-cols-3 gap-3">
          <div className="rounded-2xl bg-white/10 p-3 text-center backdrop-blur-sm">
            <p className="text-2xl font-bold text-white">{durationMinutes}</p>
            <p className="text-xs text-white/60">min</p>
          </div>
          <div className="rounded-2xl bg-white/10 p-3 text-center backdrop-blur-sm">
            <p className="text-2xl font-bold text-primary-300">{volumeDisplay}</p>
            <p className="text-xs text-white/60">volume</p>
          </div>
          <div className="rounded-2xl bg-white/10 p-3 text-center backdrop-blur-sm">
            <p className="text-2xl font-bold text-white">{exerciseCount}</p>
            <p className="text-xs text-white/60">exercícios</p>
          </div>
        </div>

        {/* Muscle badges */}
        {muscles.length > 0 && (
          <div className="relative mb-5 flex flex-wrap gap-1.5">
            {muscles.slice(0, 4).map((m) => (
              <span key={m} className="rounded-full bg-primary-500/20 border border-primary-500/30 px-2.5 py-1 text-xs font-medium text-primary-300">
                {MUSCLE_LABELS[m] ?? m}
              </span>
            ))}
          </div>
        )}

        {/* Phrase */}
        <div className="relative border-t border-white/10 pt-4">
          <p className="text-sm italic text-white/70">&ldquo;{phrase}&rdquo;</p>
        </div>
      </div>
    );
  }
);

ShareCard.displayName = "ShareCard";

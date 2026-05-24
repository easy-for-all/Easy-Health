"use client";

import { useEffect } from "react";
import confetti from "canvas-confetti";

type ConfettiPreset = "workout" | "pr" | "streak";

const presets: Record<ConfettiPreset, () => void> = {
  workout: () => {
    confetti({
      particleCount: 120,
      spread: 80,
      origin: { y: 0.6 },
      colors: ["#22c55e", "#3b82f6", "#a855f7", "#f59e0b"],
    });
  },
  pr: () => {
    confetti({
      particleCount: 60,
      angle: 60,
      spread: 55,
      origin: { x: 0 },
      colors: ["#eab308", "#f59e0b", "#fbbf24"],
    });
    confetti({
      particleCount: 60,
      angle: 120,
      spread: 55,
      origin: { x: 1 },
      colors: ["#eab308", "#f59e0b", "#fbbf24"],
    });
  },
  streak: () => {
    confetti({
      particleCount: 80,
      spread: 60,
      origin: { y: 0.5 },
      colors: ["#f97316", "#fb923c", "#fbbf24"],
    });
  },
};

type ConfettiBurstProps = {
  preset?: ConfettiPreset;
  trigger?: boolean;
};

export function ConfettiBurst({ preset = "workout", trigger = true }: ConfettiBurstProps) {
  useEffect(() => {
    if (trigger) {
      const timer = setTimeout(() => presets[preset](), 200);
      return () => clearTimeout(timer);
    }
  }, [preset, trigger]);

  return null;
}

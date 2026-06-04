"use client";

import { motion, type TargetAndTransition } from "framer-motion";

export type TrainerMood = "idle" | "speaking" | "celebrating" | "thinking";
export type TrainerSize = "sm" | "md" | "lg";

const SIZES: Record<TrainerSize, { width: number; height: number; className: string }> = {
  sm: { width: 40, height: 52, className: "w-10 h-13" },
  md: { width: 56, height: 72, className: "w-14 h-18" },
  lg: { width: 72, height: 92, className: "w-18 h-23" },
};

const moodVariants: Record<TrainerMood, TargetAndTransition> = {
  idle: {
    y: [0, -2, 0],
    scaleY: [1, 1.02, 1],
    transition: { duration: 3, repeat: Infinity, ease: "easeInOut" },
  },
  speaking: {
    y: [0, -4, 0, -2, 0],
    transition: { duration: 0.6, repeat: Infinity, ease: "easeInOut" },
  },
  celebrating: {
    y: [0, -12, 0, -8, 0],
    rotate: [0, -5, 5, -3, 3, 0],
    transition: { duration: 0.5, repeat: Infinity, ease: "easeOut" },
  },
  thinking: {
    rotate: [-3, 3, -3],
    y: [0, -1, 0],
    transition: { duration: 2, repeat: Infinity, ease: "easeInOut" },
  },
};

type Props = {
  mood?: TrainerMood;
  size?: TrainerSize;
  className?: string;
};

export function AITrainerAvatar({ mood = "idle", size = "md", className = "" }: Props) {
  const { width, height } = SIZES[size];
  const scale = width / 64;

  return (
    <motion.div
      className={`inline-block select-none ${className}`}
      animate={moodVariants[mood]}
    >
      <svg
        width={width}
        height={height}
        viewBox="0 0 64 82"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        aria-hidden="true"
      >
        <defs>
          <linearGradient id="trainerBody" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#3b82f6" />
            <stop offset="100%" stopColor="#1d4ed8" />
          </linearGradient>
          <linearGradient id="trainerHead" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#60a5fa" />
            <stop offset="100%" stopColor="#3b82f6" />
          </linearGradient>
          <radialGradient id="trainerGlow" cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor="#3b82f6" stopOpacity="0.4" />
            <stop offset="100%" stopColor="#3b82f6" stopOpacity="0" />
          </radialGradient>
          <filter id="glow">
            <feGaussianBlur stdDeviation="1.5" result="coloredBlur" />
            <feMerge>
              <feMergeNode in="coloredBlur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        {/* Glow base */}
        <ellipse cx="32" cy="74" rx="18" ry="5" fill="url(#trainerGlow)" opacity="0.6" />

        {/* Head */}
        <circle cx="32" cy="16" r="13" fill="url(#trainerHead)" filter="url(#glow)" />

        {/* Head highlight */}
        <ellipse cx="28" cy="11" rx="5" ry="4" fill="white" opacity="0.2" />

        {/* Neck */}
        <rect x="27" y="27" width="10" height="6" rx="3" fill="url(#trainerBody)" />

        {/* Torso — athletic V-shape */}
        <path
          d="M14 36 C10 44 9 56 10 68 L54 68 C55 56 54 44 50 36 C44 32 20 32 14 36Z"
          fill="url(#trainerBody)"
        />

        {/* Torso highlight strip */}
        <path
          d="M28 36 L36 36 L34 62 L30 62Z"
          fill="white"
          opacity="0.08"
        />

        {/* Left arm */}
        <path
          d="M15 37 C8 42 5 52 6 62"
          stroke="url(#trainerBody)"
          strokeWidth="9"
          strokeLinecap="round"
          fill="none"
        />

        {/* Right arm */}
        <path
          d="M49 37 C56 42 59 52 58 62"
          stroke="url(#trainerBody)"
          strokeWidth="9"
          strokeLinecap="round"
          fill="none"
        />

        {/* Left hand */}
        <circle cx="6" cy="63" r="5" fill="#3b82f6" />

        {/* Right hand */}
        <circle cx="58" cy="63" r="5" fill="#3b82f6" />

        {/* Chest accent line */}
        <path
          d="M26 40 L32 45 L38 40"
          stroke="white"
          strokeWidth="1.5"
          strokeLinecap="round"
          strokeLinejoin="round"
          opacity="0.3"
          fill="none"
        />

        {/* Celebrating star (only visible in celebrating mood) */}
        {mood === "celebrating" && (
          <motion.text
            x="48"
            y="14"
            fontSize="12"
            textAnchor="middle"
            initial={{ opacity: 0, scale: 0 }}
            animate={{ opacity: [0, 1, 0], scale: [0, 1.2, 0] }}
            transition={{ duration: 0.5, repeat: Infinity }}
          >
            ✨
          </motion.text>
        )}

        {/* Thinking dots (only visible in thinking mood) */}
        {mood === "thinking" && (
          <>
            {[0, 1, 2].map((i) => (
              <motion.circle
                key={i}
                cx={44 + i * 6}
                cy={6}
                r={2}
                fill="#93c5fd"
                initial={{ opacity: 0.3 }}
                animate={{ opacity: [0.3, 1, 0.3] }}
                transition={{ duration: 1, repeat: Infinity, delay: i * 0.2 }}
              />
            ))}
          </>
        )}
      </svg>
    </motion.div>
  );
}

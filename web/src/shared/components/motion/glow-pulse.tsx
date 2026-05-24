"use client";

import { motion } from "framer-motion";

type GlowColor = "green" | "gold" | "blue" | "orange";

const glowColors: Record<GlowColor, { idle: string; active: string }> = {
  green:  { idle: "rgba(34,197,94,0.3)",  active: "rgba(34,197,94,0.7)"  },
  gold:   { idle: "rgba(234,179,8,0.3)",  active: "rgba(234,179,8,0.7)"  },
  blue:   { idle: "rgba(59,130,246,0.3)", active: "rgba(59,130,246,0.7)" },
  orange: { idle: "rgba(249,115,22,0.3)", active: "rgba(249,115,22,0.7)" },
};

type GlowPulseProps = {
  color?: GlowColor;
  className?: string;
  children: React.ReactNode;
  radius?: number;
};

export function GlowPulse({ color = "green", className, children, radius = 12 }: GlowPulseProps) {
  const { idle, active } = glowColors[color];

  return (
    <motion.div
      className={className}
      animate={{
        boxShadow: [
          `0 0 8px 0 ${idle}`,
          `0 0 20px 4px ${active}`,
          `0 0 8px 0 ${idle}`,
        ],
      }}
      transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
      style={{ borderRadius: radius }}
    >
      {children}
    </motion.div>
  );
}

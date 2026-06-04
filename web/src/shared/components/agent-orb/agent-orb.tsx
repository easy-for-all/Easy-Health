"use client";

import "./agent-orb.css";

export type OrbSize = "fab" | "header" | "avatar" | "card";

const SIZE_PX: Record<OrbSize, number> = {
  fab: 58,
  header: 46,
  avatar: 28,
  card: 34,
};

const GLYPH_PX: Record<OrbSize, number> = {
  fab: 25,
  header: 20,
  avatar: 12,
  card: 16,
};

type AgentOrbProps = {
  size: OrbSize;
  glyph?: boolean;
  pulse?: boolean;
  className?: string;
};

export function AgentOrb({ size, glyph = false, pulse = false, className = "" }: AgentOrbProps) {
  const px = SIZE_PX[size];
  const glyphPx = GLYPH_PX[size];

  return (
    <span
      className={`agent-orb agent-orb--${size} ${pulse ? "agent-orb--pulse" : ""} ${className}`}
      style={{ width: px, height: px }}
      aria-hidden="true"
    >
      {glyph && (
        <svg
          width={glyphPx}
          height={glyphPx}
          viewBox="0 0 24 24"
          fill="none"
          stroke="white"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6L12 3z" />
          <path d="M19 14l.7 1.9L21.6 17l-1.9.7L19 19.6l-.7-1.9L16.4 17l1.9-.7L19 14z" />
        </svg>
      )}
    </span>
  );
}

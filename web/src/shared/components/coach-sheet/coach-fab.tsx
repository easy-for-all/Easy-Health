"use client";

import { AgentOrb } from "@/shared/components/agent-orb";
import { useCoach } from "@/features/coach/coach-context";

export function CoachFab() {
  const { open } = useCoach();

  return (
    <button
      onClick={() => open()}
      aria-label="Abrir Coach EasyHealth"
      style={{
        position: "fixed",
        bottom: "88px",
        right: "16px",
        zIndex: 40,
        background: "none",
        border: "none",
        padding: 0,
        cursor: "pointer",
        width: 58,
        height: 58,
      }}
    >
      <AgentOrb size="fab" glyph pulse />
    </button>
  );
}

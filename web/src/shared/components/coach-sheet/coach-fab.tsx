"use client";

import { usePathname } from "next/navigation";
import { AgentOrb } from "@/shared/components/agent-orb";
import { useCoach } from "@/features/coach/coach-context";

const IMMERSIVE_PREFIXES = ["/personal", "/join", "/plan/ai-chat"];

export function CoachFab() {
  const { open } = useCoach();
  const pathname = usePathname();

  if (IMMERSIVE_PREFIXES.some((prefix) => pathname.startsWith(prefix))) {
    return null;
  }

  return (
    <button
      onClick={() => open()}
      aria-label="Abrir Coach EasyHealth"
      style={{
        position: "fixed",
        bottom: "calc(88px + var(--safe-area-bottom))",
        right: "max(16px, var(--safe-area-right))",
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

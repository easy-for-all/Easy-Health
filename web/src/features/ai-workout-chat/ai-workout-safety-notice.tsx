"use client";

import { AI_CHAT_COLORS } from "./theme";

export function AiWorkoutSafetyNotice({ notes }: { notes: string[] }) {
  if (notes.length === 0) return null;

  return (
    <ul style={{ margin: 0, padding: "0 0 0 16px", display: "flex", flexDirection: "column", gap: 4 }}>
      {notes.map((note, i) => (
        <li key={i} style={{ fontSize: 12, color: AI_CHAT_COLORS.textDim, lineHeight: 1.4 }}>
          {note}
        </li>
      ))}
    </ul>
  );
}

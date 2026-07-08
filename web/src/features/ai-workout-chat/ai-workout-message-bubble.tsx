"use client";

import { AgentOrb } from "@/shared/components/agent-orb";
import type { WorkoutChatMessage } from "./types";

export function AiWorkoutMessageBubble({ message }: { message: WorkoutChatMessage }) {
  if (message.role === "assistant") {
    return (
      <div className="coach-msg coach-msg--ai">
        <AgentOrb size="avatar" />
        <div className="coach-bubble coach-bubble--ai">
          {message.blocked && <span aria-hidden style={{ marginRight: 6 }}>⚠️</span>}
          {message.content}
        </div>
      </div>
    );
  }

  return (
    <div className="coach-msg coach-msg--user">
      <div className="coach-bubble coach-bubble--user">{message.content}</div>
    </div>
  );
}

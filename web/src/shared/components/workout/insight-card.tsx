"use client";

import { AgentOrb } from "@/shared/components/agent-orb";
import "./workout-ui.css";

type InsightCardProps = {
  text: string;
  title?: string;
};

export function InsightCard({ text, title = "Coach EasyHealth" }: InsightCardProps) {
  return (
    <div className="insight-card">
      <div className="ic-head">
        <AgentOrb size="card" glyph />
        <b>{title}</b>
        <span className="ic-tag">IA</span>
      </div>
      <p dangerouslySetInnerHTML={{ __html: text }} />
    </div>
  );
}

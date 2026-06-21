"use client";

import Link from "next/link";
import { AgentOrb } from "@/shared/components/agent-orb";
import "./workout-ui.css";

type InsightCardProps = {
  text: string;
  title?: string;
  actionLabel?: string;
  actionHref?: string;
  onDismiss?: () => void;
};

export function InsightCard({ text, title = "Coach EasyHealth", actionLabel, actionHref, onDismiss }: InsightCardProps) {
  return (
    <div className="insight-card">
      <div className="ic-head">
        <AgentOrb size="card" glyph />
        <b>{title}</b>
        <span className="ic-tag">IA</span>
        {onDismiss && (
          <button
            onClick={onDismiss}
            style={{ marginLeft: "auto", background: "none", border: "none", cursor: "pointer", color: "var(--text-dim)", fontSize: 18, lineHeight: 1, padding: "0 2px" }}
            aria-label="Dispensar"
          >
            ×
          </button>
        )}
      </div>
      <p dangerouslySetInnerHTML={{ __html: text }} />
      {actionLabel && actionHref && (
        <Link
          href={actionHref}
          style={{
            display: "inline-block", marginTop: 8, padding: "7px 14px",
            borderRadius: "var(--r-pill)", background: "var(--primary)", color: "var(--on-primary)",
            fontSize: 12, fontWeight: 700, textDecoration: "none",
          }}
        >
          {actionLabel}
        </Link>
      )}
    </div>
  );
}

"use client";

import { useState } from "react";
import { IconLink, IconShare } from "../icons";

interface CodeCardProps {
  code: string;
  label?: string;
  hint?: string;
  onShare?: () => void;
}

export function CodeCard({ code, label = "Seu código de convite", hint, onShare }: CodeCardProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // fallback: select text
    }
  };

  return (
    <div
      style={{
        borderRadius: "var(--r-lg)",
        background: "linear-gradient(135deg, var(--primary) 0%, oklch(0.55 0.22 280) 100%)",
        padding: "20px 20px 16px",
        color: "var(--on-primary)",
      }}
    >
      <p style={{ fontSize: 12, fontWeight: 700, letterSpacing: "0.1em", textTransform: "uppercase", opacity: 0.75, marginBottom: 8 }}>
        {label}
      </p>

      <p
        style={{
          fontFamily: "var(--font-mono)",
          fontSize: 28,
          fontWeight: 700,
          letterSpacing: "0.15em",
          margin: "0 0 16px",
        }}
      >
        {code}
      </p>

      {hint && (
        <p style={{ fontSize: 12, opacity: 0.7, marginBottom: 16 }}>{hint}</p>
      )}

      <div style={{ display: "flex", gap: 8 }}>
        <button
          onClick={handleCopy}
          aria-label="Copiar código"
          style={{
            flex: 1,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 6,
            padding: "9px 12px",
            borderRadius: "var(--r-sm)",
            background: "rgba(255,255,255,0.18)",
            border: "1px solid rgba(255,255,255,0.22)",
            color: "var(--on-primary)",
            fontSize: 13,
            fontWeight: 600,
            cursor: "pointer",
            transition: "background .18s",
            minHeight: 44,
          }}
        >
          <IconLink className="w-4 h-4" />
          {copied ? "Copiado!" : "Copiar"}
        </button>

        {onShare && (
          <button
            onClick={onShare}
            aria-label="Compartilhar código"
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: 6,
              padding: "9px 16px",
              borderRadius: "var(--r-sm)",
              background: "rgba(255,255,255,0.18)",
              border: "1px solid rgba(255,255,255,0.22)",
              color: "var(--on-primary)",
              fontSize: 13,
              fontWeight: 600,
              cursor: "pointer",
              minHeight: 44,
            }}
          >
            <IconShare className="w-4 h-4" />
            Compartilhar
          </button>
        )}
      </div>
    </div>
  );
}

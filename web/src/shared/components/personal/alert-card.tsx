"use client";

import { IconPause, IconTrophy, IconAlertTri, IconTrendUp2, IconBell } from "../icons";

export type AlertKind = "pause" | "trophy" | "warning" | "trend" | "info";

export interface Alert {
  id: number;
  kind: AlertKind;
  title: string;
  body: string;
  unread?: boolean;
  time?: string;
}

interface AlertCardProps {
  alert: Alert;
  onRead?: (id: number) => void;
}

const KIND_CONFIG: Record<AlertKind, { Icon: React.FC<{ className?: string }>; color: string; bg: string }> = {
  pause:   { Icon: IconPause,    color: "var(--hot)",     bg: "var(--hot-soft)"     },
  trophy:  { Icon: IconTrophy,   color: "oklch(0.72 0.18 78)", bg: "oklch(0.72 0.18 78 / 0.14)" },
  warning: { Icon: IconAlertTri, color: "var(--warn)",    bg: "var(--warn-soft)"    },
  trend:   { Icon: IconTrendUp2, color: "var(--good)",    bg: "var(--good-soft)"    },
  info:    { Icon: IconBell,     color: "var(--primary)", bg: "var(--primary-soft)" },
};

export function AlertCard({ alert, onRead }: AlertCardProps) {
  const cfg = KIND_CONFIG[alert.kind];
  const { Icon } = cfg;

  return (
    <button
      onClick={() => onRead?.(alert.id)}
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: 12,
        padding: "14px 16px",
        background: "var(--surface)",
        borderRadius: "var(--r-lg)",
        border: `1px solid ${alert.unread ? cfg.color : "var(--border)"}`,
        textAlign: "left",
        cursor: "pointer",
        width: "100%",
        transition: "border-color .18s",
        position: "relative",
      }}
      aria-label={alert.title}
    >
      {/* Unread dot */}
      {alert.unread && (
        <span
          style={{
            position: "absolute",
            top: 14,
            right: 14,
            width: 8,
            height: 8,
            borderRadius: "50%",
            background: cfg.color,
          }}
        />
      )}

      {/* Icon */}
      <div
        style={{
          width: 36,
          height: 36,
          borderRadius: "var(--r-sm)",
          background: cfg.bg,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexShrink: 0,
          color: cfg.color,
        }}
      >
        <Icon className="w-5 h-5" />
      </div>

      {/* Content */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <p style={{ margin: 0, fontWeight: 700, fontSize: 14, color: "var(--text)", lineHeight: 1.3 }}>
          {alert.title}
        </p>
        <p style={{ margin: "3px 0 0", fontSize: 13, color: "var(--text-muted)", lineHeight: 1.4 }}>
          {alert.body}
        </p>
        {alert.time && (
          <p style={{ margin: "4px 0 0", fontSize: 11, color: "var(--text-dim)" }}>
            {alert.time}
          </p>
        )}
      </div>
    </button>
  );
}

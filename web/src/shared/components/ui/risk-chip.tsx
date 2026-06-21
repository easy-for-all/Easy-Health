type RiskLevel = "high" | "med" | "low";

interface RiskChipProps {
  level: RiskLevel;
  label?: string;
}

const RISK_STYLES: Record<RiskLevel, { bg: string; color: string; defaultLabel: string }> = {
  high: { bg: "var(--hot-soft)",  color: "var(--hot)",  defaultLabel: "Risco alto"  },
  med:  { bg: "var(--warn-soft)", color: "var(--warn)", defaultLabel: "Atenção"     },
  low:  { bg: "var(--good-soft)", color: "var(--good)", defaultLabel: "Em dia"      },
};

export function RiskChip({ level, label }: RiskChipProps) {
  const s = RISK_STYLES[level];
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 4,
        padding: "3px 8px",
        borderRadius: "var(--r-pill)",
        fontSize: 11,
        fontWeight: 700,
        background: s.bg,
        color: s.color,
        whiteSpace: "nowrap",
      }}
    >
      <span
        style={{
          width: 6,
          height: 6,
          borderRadius: "50%",
          background: s.color,
          flexShrink: 0,
        }}
      />
      {label ?? s.defaultLabel}
    </span>
  );
}

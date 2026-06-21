interface AdherenceRingProps {
  pct: number;
  size?: number;
  strokeWidth?: number;
  showLabel?: boolean;
}

function colorForPct(pct: number): string {
  if (pct >= 80) return "var(--good)";
  if (pct >= 50) return "var(--warn)";
  return "var(--hot)";
}

export function AdherenceRing({ pct, size = 52, strokeWidth = 5, showLabel = true }: AdherenceRingProps) {
  const r = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * r;
  const offset = circumference - (pct / 100) * circumference;
  const color = colorForPct(pct);
  const center = size / 2;

  return (
    <div style={{ position: "relative", width: size, height: size, flexShrink: 0 }}>
      <svg width={size} height={size} style={{ transform: "rotate(-90deg)" }}>
        <circle
          cx={center} cy={center} r={r}
          fill="none"
          stroke="var(--surface-3)"
          strokeWidth={strokeWidth}
        />
        <circle
          cx={center} cy={center} r={r}
          fill="none"
          stroke={color}
          strokeWidth={strokeWidth}
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          strokeLinecap="round"
          style={{ transition: "stroke-dashoffset .5s var(--ease)" }}
        />
      </svg>
      {showLabel && (
        <span
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: size * 0.22,
            fontWeight: 700,
            color,
            fontFamily: "var(--font-display)",
            fontVariantNumeric: "tabular-nums",
          }}
        >
          {Math.round(pct)}%
        </span>
      )}
    </div>
  );
}

type StatusKind = "ok" | "pend" | "warn";

interface StatusPillProps {
  kind: StatusKind;
  label: string;
}

const STATUS_STYLES: Record<StatusKind, { bg: string; color: string }> = {
  ok:   { bg: "var(--good-soft)", color: "var(--good)" },
  pend: { bg: "var(--warn-soft)", color: "var(--warn)" },
  warn: { bg: "var(--hot-soft)",  color: "var(--hot)"  },
};

export function StatusPill({ kind, label }: StatusPillProps) {
  const s = STATUS_STYLES[kind];
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        padding: "3px 10px",
        borderRadius: "var(--r-pill)",
        fontSize: 11,
        fontWeight: 700,
        letterSpacing: "0.04em",
        textTransform: "uppercase",
        background: s.bg,
        color: s.color,
        whiteSpace: "nowrap",
      }}
    >
      {label}
    </span>
  );
}

import { CheckStatus, MetricUnit } from "./types";

// The honest cell.
//
// It is deliberately IMPOSSIBLE to render a percentage here without a value.
// `value === null` means the backend could not measure — because the sample was
// below the floor, or because nothing happened at all — and printing "0%" for
// that is a factual error, not a formatting choice. The same discipline as the
// Cell in admin/platform-comparison-section.tsx.

export function formatValue(value: number | null, unit: MetricUnit): string | null {
  if (value === null || value === undefined || Number.isNaN(value)) return null;

  if (unit === "count") return value.toLocaleString("pt-BR");
  if (unit === "seconds") return `${value.toLocaleString("pt-BR", { maximumFractionDigits: 2 })}s`;
  return `${(value * 100).toLocaleString("pt-BR", { maximumFractionDigits: 1 })}%`;
}

export function MetricValue({
  value,
  unit,
  status,
  sampleSize,
  className = "",
}: {
  value: number | null;
  unit: MetricUnit;
  status: CheckStatus;
  sampleSize?: number | null;
  className?: string;
}) {
  const formatted = formatValue(value, unit);

  if (formatted === null || status === "insufficient_data") {
    return (
      <span className={`text-sm text-[var(--text-dim)] ${className}`}>
        amostra insuficiente
        {typeof sampleSize === "number" ? ` (n=${sampleSize.toLocaleString("pt-BR")})` : ""}
      </span>
    );
  }

  return (
    <span className={className}>
      {formatted}
      {typeof sampleSize === "number" && sampleSize > 0 && unit === "ratio" ? (
        <span className="ml-1 text-xs font-normal text-[var(--text-dim)]">
          (n={sampleSize.toLocaleString("pt-BR")})
        </span>
      ) : null}
    </span>
  );
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

export function formatDuration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined) return "—";
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}min`;
  if (seconds < 86400) return `${(seconds / 3600).toFixed(1)}h`;
  return `${(seconds / 86400).toFixed(1)}d`;
}

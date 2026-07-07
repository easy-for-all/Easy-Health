export function StatCard({
  label, value, description, pct,
}: {
  label: string;
  value: number | string | undefined;
  description?: string;
  pct?: boolean;
}) {
  const display = value === undefined ? "—" : pct ? `${value}%` : typeof value === "number" ? value.toLocaleString("pt-BR") : value;
  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <p className="text-2xl font-bold text-primary-600">{display}</p>
      <p className="mt-1 text-sm font-semibold text-[var(--text)]">{label}</p>
      {description && <p className="mt-0.5 text-xs text-[var(--text-dim)]">{description}</p>}
    </div>
  );
}

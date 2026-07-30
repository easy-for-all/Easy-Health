// Big-number card used across the admin dashboard. Moved out of page.tsx so the
// cohort summary can reuse it without importing from the page component (which
// would be a circular import, since the page renders the summary).
export function StatCard({
  label, value, description, pct,
}: {
  label: string;
  value: number | string | undefined;
  description?: string;
  pct?: boolean;
}) {
  const display =
    value === undefined || value === null
      ? "—"
      : pct
        ? `${value}%`
        : typeof value === "number"
          ? value.toLocaleString("pt-BR")
          : value;

  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <p className="text-3xl font-bold text-primary-600">{display}</p>
      <p className="mt-1 text-sm font-semibold text-[var(--text)]">{label}</p>
      {description && <p className="mt-0.5 text-xs text-[var(--text-dim)]">{description}</p>}
    </div>
  );
}

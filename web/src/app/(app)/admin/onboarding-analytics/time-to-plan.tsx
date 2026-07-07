import type { OnboardingAnalytics } from "./types";
import { EmptyState } from "./empty-state";

export function TimeToPlan({ data }: { data: OnboardingAnalytics["time_to_first_plan"] }) {
  const entries = Object.entries(data).filter(([, entry]) => entry.count > 0);
  if (entries.length === 0) return <EmptyState />;

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
      {entries.map(([key, entry]) => (
        <div key={key} className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
          <p className="text-2xl font-bold text-primary-600">{entry.avg_label ?? "—"}</p>
          <p className="mt-1 text-sm font-semibold text-[var(--text)]">{entry.label}</p>
          <p className="mt-0.5 text-xs text-[var(--text-dim)]">
            Tempo médio · mediana {entry.median_label ?? "—"} · {entry.count} usuários
          </p>
        </div>
      ))}
    </div>
  );
}

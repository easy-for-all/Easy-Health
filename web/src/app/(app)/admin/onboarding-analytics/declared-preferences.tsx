import type { OnboardingAnalytics, PreferenceEntry } from "./types";
import { EmptyState } from "./empty-state";

function PreferenceBars({ title, entries }: { title: string; entries: PreferenceEntry[] }) {
  if (entries.length === 0) return null;

  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <p className="mb-3 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">{title}</p>
      <div className="space-y-2">
        {entries.map((entry) => (
          <div key={entry.key} className="flex items-center gap-3">
            <div className="w-32 shrink-0 truncate text-xs text-[var(--text-muted)]">{entry.label}</div>
            <div className="h-2 flex-1 overflow-hidden rounded-full bg-[var(--border)]">
              <div className="h-full rounded-full bg-primary-500" style={{ width: `${Math.max(entry.pct, 2)}%` }} />
            </div>
            <div className="w-14 shrink-0 text-right text-xs font-medium text-[var(--text)]">{entry.pct}%</div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function DeclaredPreferences({ data }: { data: OnboardingAnalytics["declared_preferences"] }) {
  const hasData = data.goals.length > 0 || data.locations.length > 0;
  if (!hasData) return <EmptyState />;

  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <PreferenceBars title="Objetivos" entries={data.goals} />
      <PreferenceBars title="Local de treino" entries={data.locations} />
      <PreferenceBars title="Tempo por treino" entries={data.durations} />
      <PreferenceBars title="Vezes por semana" entries={data.frequencies} />
      <PreferenceBars title="Limitações" entries={data.limitations} />
      <PreferenceBars title="Intensidade preferida" entries={data.training_preference.intensity} />
      <PreferenceBars title="Estilo de treino" entries={data.training_preference.style} />
    </div>
  );
}

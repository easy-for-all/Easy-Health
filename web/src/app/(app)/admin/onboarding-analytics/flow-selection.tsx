import type { OnboardingAnalytics } from "./types";
import { StatCard } from "./stat-card";
import { EmptyState } from "./empty-state";

export function FlowSelection({ data }: { data: OnboardingAnalytics["flow_selection"] }) {
  if (data.total === 0) return <EmptyState />;

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
      {Object.entries(data.by_flow).map(([key, entry]) => (
        <StatCard key={key} label={entry.label} value={entry.count} description={`${entry.pct}% do total`} />
      ))}
    </div>
  );
}

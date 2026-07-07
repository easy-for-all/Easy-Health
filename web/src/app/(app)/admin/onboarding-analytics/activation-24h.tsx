import type { OnboardingAnalytics } from "./types";
import { StatCard } from "./stat-card";
import { EmptyState } from "./empty-state";

export function Activation24h({ data }: { data: OnboardingAnalytics["first_workout_24h"] }) {
  const { overall, by_flow } = data;
  const hasOverall = overall.signup_to_first_workout_24h > 0 || overall.plan_to_first_workout_24h > 0;
  const flowEntries = Object.entries(by_flow).filter(([, entry]) => entry.activated_24h > 0);

  if (!hasOverall && flowEntries.length === 0) return <EmptyState />;

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatCard
          label="Cadastro → 1º treino em 24h"
          value={overall.signup_to_first_workout_24h_pct}
          description={`${overall.signup_to_first_workout_24h} usuários`}
          pct
        />
        <StatCard
          label="Plano criado → 1º treino em 24h"
          value={overall.plan_to_first_workout_24h_pct}
          description={`${overall.plan_to_first_workout_24h} usuários`}
          pct
        />
        <StatCard label="Tempo médio até 1º treino" value={overall.avg_time_label ?? "—"} />
        <StatCard label="Tempo mediano até 1º treino" value={overall.median_time_label ?? "—"} />
      </div>

      {flowEntries.length > 0 && (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {flowEntries.map(([key, entry]) => (
            <StatCard key={key} label={entry.label} value={entry.activated_24h_pct} description={`${entry.activated_24h} usuários`} pct />
          ))}
        </div>
      )}
    </div>
  );
}

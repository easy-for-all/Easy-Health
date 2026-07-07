import type { OnboardingAnalytics } from "./types";
import { EmptyState } from "./empty-state";

export function ConversionByFlowTable({ data }: { data: OnboardingAnalytics["conversion_by_flow"] }) {
  const rows = Object.values(data);
  const hasData = rows.some((row) => row.selected > 0);
  if (!hasData) return <EmptyState />;

  return (
    <div className="overflow-x-auto rounded-2xl border border-[var(--border)] bg-[var(--surface)]">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-[var(--border)] text-left text-xs text-[var(--text-muted)]">
            <th className="px-4 py-3 font-medium">Fluxo</th>
            <th className="px-4 py-3 font-medium text-center">Escolheram</th>
            <th className="px-4 py-3 font-medium text-center">Criaram treino</th>
            <th className="px-4 py-3 font-medium text-center">Executaram 1º</th>
            <th className="px-4 py-3 font-medium text-center">2+ treinos</th>
            <th className="px-4 py-3 font-medium text-center">3+ treinos</th>
            <th className="px-4 py-3 font-medium text-center">Assinaram</th>
            <th className="px-4 py-3 font-medium text-center">Conv. treino</th>
            <th className="px-4 py-3 font-medium text-center">Conv. assinatura</th>
          </tr>
        </thead>
        <tbody>
          {Object.entries(data).map(([key, row]) => (
            <tr key={key} className="border-b border-[var(--border)] last:border-0">
              <td className="px-4 py-3 font-medium text-[var(--text)]">{row.label}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.selected}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.created_workout}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.executed_first}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.plus2_sessions}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.plus3_sessions}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.subscribed}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.conversion_to_workout_pct}%</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.conversion_to_subscription_pct}%</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

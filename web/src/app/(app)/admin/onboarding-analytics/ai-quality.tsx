import type { OnboardingAnalytics } from "./types";
import { EmptyState } from "./empty-state";

export function AiQuality({ data }: { data: OnboardingAnalytics["ai_quality"] }) {
  const rows = Object.entries(data);
  const hasData = rows.some(([, row]) => row.summaries_generated > 0);
  if (!hasData) return <EmptyState />;

  return (
    <div className="overflow-x-auto rounded-2xl border border-[var(--border)] bg-[var(--surface)]">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-[var(--border)] text-left text-xs text-[var(--text-muted)]">
            <th className="px-4 py-3 font-medium">Fluxo IA</th>
            <th className="px-4 py-3 font-medium text-center">Resumos gerados</th>
            <th className="px-4 py-3 font-medium text-center">Editados</th>
            <th className="px-4 py-3 font-medium text-center">Aceito sem edição</th>
            <th className="px-4 py-3 font-medium text-center">Recriados</th>
            <th className="px-4 py-3 font-medium text-center">Abandonados</th>
            <th className="px-4 py-3 font-medium text-center">Taxa de aceite</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(([key, row]) => (
            <tr key={key} className="border-b border-[var(--border)] last:border-0">
              <td className="px-4 py-3 font-medium text-[var(--text)]">{row.label}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.summaries_generated}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.summaries_edited}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.plans_accepted}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.plans_regenerated}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.plans_abandoned}</td>
              <td className="px-4 py-3 text-center text-[var(--text)]">{row.acceptance_pct}%</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

import type { OnboardingAnalytics } from "./types";
import { StatCard } from "./stat-card";
import { EmptyState } from "./empty-state";

export function ProgressiveProfilingSection({ data }: { data: OnboardingAnalytics["progressive_profiling"] }) {
  const { summary, by_question } = data;
  if (summary.shown === 0) return <EmptyState />;

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        <StatCard label="Perguntas exibidas" value={summary.shown} />
        <StatCard label="Respondidas" value={summary.answered} />
        <StatCard label="Ignoradas" value={summary.skipped} />
        <StatCard label="Taxa de resposta" value={summary.answer_rate_pct} pct />
        <StatCard label="Responder depois" value={summary.skip_rate_pct} pct />
      </div>

      <div className="overflow-x-auto rounded-2xl border border-[var(--border)] bg-[var(--surface)]">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-[var(--border)] text-left text-xs text-[var(--text-muted)]">
              <th className="px-4 py-3 font-medium">Pergunta</th>
              <th className="px-4 py-3 font-medium text-center">Exibida</th>
              <th className="px-4 py-3 font-medium text-center">Respondida</th>
              <th className="px-4 py-3 font-medium text-center">Ignorada</th>
              <th className="px-4 py-3 font-medium text-center">Taxa</th>
              <th className="px-4 py-3 font-medium">Principal resposta</th>
            </tr>
          </thead>
          <tbody>
            {by_question.map((q) => (
              <tr key={q.question_key} className="border-b border-[var(--border)] last:border-0">
                <td className="px-4 py-3 font-medium text-[var(--text)]">{q.label}</td>
                <td className="px-4 py-3 text-center text-[var(--text)]">{q.shown}</td>
                <td className="px-4 py-3 text-center text-[var(--text)]">{q.answered}</td>
                <td className="px-4 py-3 text-center text-[var(--text)]">{q.skipped}</td>
                <td className="px-4 py-3 text-center text-[var(--text)]">{q.answer_rate_pct}%</td>
                <td className="px-4 py-3 text-[var(--text-muted)]">{q.top_answer ?? "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

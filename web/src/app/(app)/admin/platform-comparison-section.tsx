"use client";

// "Impacto do app Android" (Fase 15) — the central observational comparison.
// ADMIN ONLY (the whole /admin page is gated by user.admin). Reads the
// auditable product_analytics_events cohorts by activation_platform. Every cell
// carries numerator/denominator/status so small early cohorts read as
// "amostra insuficiente" instead of a misleading percentage.
import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";

interface Metric {
  value: number;
  numerator: number;
  denominator: number;
  status: string;
  cohort_maturity?: string;
  definition: string;
}

interface Cohort {
  cohort_size: number;
  created_workout: Metric;
  completed_workout: Metric;
  activation_24h: Metric;
  retention_value_d7: Metric;
}

interface Payload {
  cohorts: Record<string, Cohort>;
  note: string;
  coverage: string;
  generated_at: string;
}

const COHORT_LABELS: Record<string, string> = {
  android: "Android",
  web: "Web",
  pwa: "PWA",
};

const ROWS: { key: keyof Omit<Cohort, "cohort_size">; label: string }[] = [
  { key: "created_workout", label: "Criou treino" },
  { key: "completed_workout", label: "Concluiu 1º treino" },
  { key: "activation_24h", label: "Ativação 24h" },
  { key: "retention_value_d7", label: "Retenção de valor D7" },
];

function Cell({ m }: { m: Metric }) {
  // Honest rendering: never show a bare % for weak/immature data.
  if (m.status === "no_coverage") {
    return <span className="text-[var(--text-dim)]">sem cobertura</span>;
  }
  if (m.cohort_maturity === "immature") {
    return <span className="text-[var(--text-dim)]" title="coorte ainda não madura">não madura</span>;
  }
  if (m.status === "insufficient_sample") {
    return (
      <span className="text-[var(--text-dim)]" title="amostra insuficiente">
        {m.numerator}/{m.denominator} · amostra baixa
      </span>
    );
  }
  return (
    <span className="font-semibold text-[var(--text)]">
      {m.value}% <span className="text-[var(--text-dim)] font-normal">({m.numerator}/{m.denominator})</span>
    </span>
  );
}

export function PlatformComparisonSection() {
  const [data, setData] = useState<Payload | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    api
      .get<Payload>("/api/v1/admin/analytics/platform_comparison")
      .then(setData)
      .catch(() => setError(true));
  }, []);

  if (error) return null;

  const cohortKeys = data ? Object.keys(data.cohorts) : [];

  return (
    <section className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <div className="mb-1 flex items-baseline justify-between gap-2">
        <h2 className="text-sm font-bold text-[var(--text)]">Impacto do app Android</h2>
        <span className="text-[10px] uppercase tracking-wide text-[var(--text-dim)]">associação observada</span>
      </div>

      {!data ? (
        <p className="text-xs text-[var(--text-dim)]">Carregando…</p>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-[var(--text-dim)]">
                  <th className="py-2 pr-3 font-medium">Métrica</th>
                  {cohortKeys.map((k) => (
                    <th key={k} className="py-2 pr-3 font-medium">
                      {COHORT_LABELS[k] ?? k}
                      <span className="ml-1 text-[var(--text-dim)]">
                        (n={data.cohorts[k].cohort_size})
                      </span>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {ROWS.map((row) => (
                  <tr key={row.key} className="border-t border-[var(--border)]">
                    <td className="py-2 pr-3 text-xs text-[var(--text-dim)]">{row.label}</td>
                    {cohortKeys.map((k) => (
                      <td key={k} className="py-2 pr-3 text-xs">
                        <Cell m={data.cohorts[k][row.key]} />
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <p className="mt-3 rounded-lg bg-[var(--bg)] p-2 text-[11px] leading-snug text-[var(--text-dim)]">
            {data.note}
          </p>
          <p className="mt-1 text-[10px] text-[var(--text-dim)]">
            Cobertura: dados próprios a partir da ativação do rastreamento (event_tracked).
          </p>
        </>
      )}
    </section>
  );
}

"use client";

import { AndroidBuildRow, CheckStatus } from "./types";
import { StatusBadge } from "./status-badge";
import { MetricValue } from "./metric-cell";

// Table 2. Per build/version, over the selected window.
//
// The rate columns go through MetricValue, so a build with three installs shows
// "amostra insuficiente" instead of a confident 33% — that distinction is the
// whole reason this table exists rather than a chart.

const RANGES: { value: string; label: string }[] = [
  { value: "24h", label: "24h" },
  { value: "7d", label: "7d" },
  { value: "30d", label: "30d" },
];

export function AndroidBuildsTable({
  rows,
  range,
  onRangeChange,
}: {
  rows: AndroidBuildRow[];
  range: string;
  onRangeChange: (range: string) => void;
}) {
  return (
    <section>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">
          Android por build
        </h2>
        <div className="flex items-center gap-1.5">
          {RANGES.map((option) => (
            <button
              key={option.value}
              type="button"
              onClick={() => onRangeChange(option.value)}
              aria-pressed={range === option.value}
              className={`rounded-full px-2.5 py-1 text-xs ${
                range === option.value
                  ? "bg-primary-500 text-white"
                  : "border border-[var(--border)] bg-[var(--surface)] text-[var(--text-muted)] hover:text-[var(--text)]"
              }`}
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>

      {rows.length === 0 ? (
        <p className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4 text-sm text-[var(--text-muted)]">
          Nenhuma instalação Android registrada na janela de {range}.
        </p>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-[var(--border)] bg-[var(--surface)]">
          <table className="w-full min-w-[860px] text-left text-sm">
            <thead>
              <tr className="text-xs uppercase tracking-wide text-[var(--text-dim)]">
                <th className="px-3 py-2">Versão</th>
                <th className="px-3 py-2">Build</th>
                <th className="px-3 py-2">Coorte</th>
                <th className="px-3 py-2">Instalações</th>
                <th className="px-3 py-2">Autenticadas</th>
                <th className="px-3 py-2">Cadastros</th>
                <th className="px-3 py-2">Vinculadas</th>
                <th className="px-3 py-2">Taxa cadastro</th>
                <th className="px-3 py-2">Taxa vínculo</th>
                <th className="px-3 py-2">Erros Google</th>
                <th className="px-3 py-2">Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={`${row.app_version}-${row.app_build}`} className="border-t border-[var(--border)]">
                  <td className="px-3 py-2 text-[var(--text)]">{row.app_version || "—"}</td>
                  <td className="px-3 py-2 text-[var(--text)]">{row.app_build || "—"}</td>
                  <td className="px-3 py-2 text-xs text-[var(--text-muted)]">{row.build_group}</td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">{row.installations.toLocaleString("pt-BR")}</td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">{row.authenticated.toLocaleString("pt-BR")}</td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">{row.registrations.toLocaleString("pt-BR")}</td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">
                    {row.linked.toLocaleString("pt-BR")}
                    <span className="ml-1 text-xs text-[var(--text-dim)]">
                      ({row.anonymous.toLocaleString("pt-BR")} anôn.)
                    </span>
                  </td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">
                    <MetricValue
                      value={row.registration_rate}
                      unit="ratio"
                      status={row.registration_rate === null ? "insufficient_data" : ("healthy" as CheckStatus)}
                      sampleSize={row.sample_size}
                    />
                  </td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">
                    <MetricValue
                      value={row.linkage_rate}
                      unit="ratio"
                      status={row.linkage_rate === null ? "insufficient_data" : ("healthy" as CheckStatus)}
                      sampleSize={row.sample_size}
                    />
                  </td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">
                    {row.google_auth_errors.toLocaleString("pt-BR")}
                  </td>
                  <td className="px-3 py-2">
                    <StatusBadge status={row.status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

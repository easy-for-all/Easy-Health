"use client";

import { HeartbeatRow } from "./types";
import { StatusBadge } from "./status-badge";
import { formatDateTime, formatDuration } from "./metric-cell";

// Table 3. The answer to "did anything just stop running?".
//
// Note "nunca" in the last-success column: a registered process that has never
// succeeded is shown explicitly rather than as a blank, because an empty cell
// reads as "no data yet" when it usually means "this never ran".

export function HeartbeatsTable({ rows }: { rows: HeartbeatRow[] }) {
  return (
    <section>
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">
        Heartbeats
      </h2>

      {rows.length === 0 ? (
        <p className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4 text-sm text-[var(--text-muted)]">
          Nenhum processo registrado. Rode: rake observability:heartbeats
        </p>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-[var(--border)] bg-[var(--surface)]">
          <table className="w-full min-w-[880px] text-left text-sm">
            <thead>
              <tr className="text-xs uppercase tracking-wide text-[var(--text-dim)]">
                <th className="px-3 py-2">Processo</th>
                <th className="px-3 py-2">Categoria</th>
                <th className="px-3 py-2">Intervalo esperado</th>
                <th className="px-3 py-2">Último início</th>
                <th className="px-3 py-2">Último sucesso</th>
                <th className="px-3 py-2">Última falha</th>
                <th className="px-3 py-2">Falhas seq.</th>
                <th className="px-3 py-2">Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.key} className="border-t border-[var(--border)]">
                  <td className="px-3 py-2 font-medium text-[var(--text)]">{row.key}</td>
                  <td className="px-3 py-2 text-xs text-[var(--text-muted)]">{row.category}</td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">
                    {formatDuration(row.expected_interval_seconds)}
                  </td>
                  <td className="px-3 py-2 text-xs text-[var(--text-muted)]">
                    {formatDateTime(row.last_started_at)}
                  </td>
                  <td className="px-3 py-2 text-xs text-[var(--text-muted)]">
                    {row.last_succeeded_at ? (
                      <>
                        {formatDateTime(row.last_succeeded_at)}
                        <span className="block text-[var(--text-dim)]">
                          há {formatDuration(row.seconds_since_success)}
                        </span>
                      </>
                    ) : (
                      <span className="text-[var(--text-dim)]">nunca</span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-xs text-[var(--text-muted)]">
                    {formatDateTime(row.last_failed_at)}
                    {row.last_error_code ? (
                      <span className="block text-[var(--text-dim)]">{row.last_error_code}</span>
                    ) : null}
                  </td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">{row.consecutive_failures}</td>
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

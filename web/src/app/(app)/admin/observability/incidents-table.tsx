"use client";

import { useState } from "react";
import { api } from "@/shared/lib/api";
import { Incident } from "./types";
import { formatDateTime, formatDuration } from "./metric-cell";

const SEVERITY_STYLE: Record<string, string> = {
  critical: "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300",
  warning: "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300",
};

const STATUS_LABEL: Record<string, string> = {
  open: "Aberto",
  acknowledged: "Reconhecido",
  resolved: "Resolvido",
};

type StatusFilter = "open" | "resolved" | "";
type SeverityFilter = "critical" | "warning" | "";

function PillGroup<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: T;
  options: { value: T; label: string }[];
  onChange: (value: T) => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      <span className="text-xs text-[var(--text-dim)]">{label}</span>
      {options.map((option) => (
        <button
          key={option.value || "all"}
          type="button"
          onClick={() => onChange(option.value)}
          aria-pressed={value === option.value}
          className={`rounded-full px-2.5 py-1 text-xs ${
            value === option.value
              ? "bg-primary-500 text-white"
              : "border border-[var(--border)] bg-[var(--surface)] text-[var(--text-muted)] hover:text-[var(--text)]"
          }`}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

export function IncidentsTable({
  incidents,
  onChanged,
}: {
  incidents: Incident[];
  onChanged: () => void;
}) {
  const [status, setStatus] = useState<StatusFilter>("");
  const [severity, setSeverity] = useState<SeverityFilter>("");
  const [source, setSource] = useState<string>("");
  const [busyId, setBusyId] = useState<number | null>(null);

  const filtered = incidents.filter((incident) => {
    if (status === "open" && incident.status === "resolved") return false;
    if (status === "resolved" && incident.status !== "resolved") return false;
    if (severity && incident.severity !== severity) return false;
    if (source && incident.source !== source) return false;
    return true;
  });

  async function act(incident: Incident, action: "acknowledge" | "resolve") {
    setBusyId(incident.id);
    try {
      await api.post(`/api/v1/admin/observability/incidents/${incident.id}/${action}`, {});
      onChanged();
    } catch {
      // Reloading restores the true server state whether or not it succeeded —
      // no optimistic local mutation to unwind.
      onChanged();
    } finally {
      setBusyId(null);
    }
  }

  return (
    <section>
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">
        Incidentes
      </h2>

      <div className="mb-3 flex flex-col gap-2">
        <PillGroup
          label="Status"
          value={status}
          onChange={setStatus}
          options={[
            { value: "" as StatusFilter, label: "Todos" },
            { value: "open" as StatusFilter, label: "Abertos" },
            { value: "resolved" as StatusFilter, label: "Resolvidos" },
          ]}
        />
        <PillGroup
          label="Severidade"
          value={severity}
          onChange={setSeverity}
          options={[
            { value: "" as SeverityFilter, label: "Todas" },
            { value: "critical" as SeverityFilter, label: "Crítico" },
            { value: "warning" as SeverityFilter, label: "Aviso" },
          ]}
        />
        <PillGroup
          label="Origem"
          value={source}
          onChange={setSource}
          options={[
            { value: "", label: "Todas" },
            { value: "internal_check", label: "Check interno" },
            { value: "manual", label: "Manual" },
          ]}
        />
      </div>

      {filtered.length === 0 ? (
        <p className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4 text-sm text-[var(--text-muted)]">
          Nenhum incidente para os filtros selecionados.
        </p>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-[var(--border)] bg-[var(--surface)]">
          <table className="w-full min-w-[900px] text-left text-sm">
            <thead>
              <tr className="text-xs uppercase tracking-wide text-[var(--text-dim)]">
                <th className="px-3 py-2">Sev.</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Título</th>
                <th className="px-3 py-2">Check</th>
                <th className="px-3 py-2">Valor</th>
                <th className="px-3 py-2">Limite</th>
                <th className="px-3 py-2">1ª detecção</th>
                <th className="px-3 py-2">Última</th>
                <th className="px-3 py-2">Ocorr.</th>
                <th className="px-3 py-2">Origem</th>
                <th className="px-3 py-2">Ações</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((incident) => (
                <tr key={incident.id} className="border-t border-[var(--border)]">
                  <td className="px-3 py-2">
                    <span
                      className={`rounded-full px-2 py-0.5 text-xs font-semibold ${SEVERITY_STYLE[incident.severity] ?? ""}`}
                    >
                      {incident.severity === "critical" ? "Crítico" : "Aviso"}
                    </span>
                  </td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">
                    {STATUS_LABEL[incident.status] ?? incident.status}
                  </td>
                  <td className="px-3 py-2">
                    <p className="font-medium text-[var(--text)]">{incident.title}</p>
                    {incident.description ? (
                      <p className="text-xs text-[var(--text-dim)]">{incident.description}</p>
                    ) : null}
                  </td>
                  <td className="px-3 py-2 text-xs text-[var(--text-muted)]">{incident.check_key ?? "—"}</td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">
                    {incident.current_value === null ? "—" : incident.current_value.toLocaleString("pt-BR")}
                  </td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">
                    {incident.threshold_value === null ? "—" : incident.threshold_value.toLocaleString("pt-BR")}
                  </td>
                  <td className="px-3 py-2 text-xs text-[var(--text-muted)]">
                    {formatDateTime(incident.first_detected_at)}
                    <span className="block text-[var(--text-dim)]">
                      {formatDuration(incident.duration_seconds)}
                    </span>
                  </td>
                  <td className="px-3 py-2 text-xs text-[var(--text-muted)]">
                    {formatDateTime(incident.last_detected_at)}
                  </td>
                  <td className="px-3 py-2 text-[var(--text-muted)]">{incident.occurrence_count}</td>
                  <td className="px-3 py-2 text-xs text-[var(--text-muted)]">{incident.source}</td>
                  <td className="px-3 py-2">
                    {incident.status === "resolved" ? (
                      <span className="text-xs text-[var(--text-dim)]">—</span>
                    ) : (
                      <div className="flex gap-1.5">
                        {incident.status === "open" ? (
                          <button
                            type="button"
                            disabled={busyId === incident.id}
                            onClick={() => act(incident, "acknowledge")}
                            className="rounded-full border border-[var(--border)] px-2.5 py-1 text-xs text-[var(--text-muted)] hover:text-[var(--text)] disabled:opacity-50"
                          >
                            Reconhecer
                          </button>
                        ) : null}
                        <button
                          type="button"
                          disabled={busyId === incident.id}
                          onClick={() => act(incident, "resolve")}
                          className="rounded-full bg-primary-500 px-2.5 py-1 text-xs text-white disabled:opacity-50"
                        >
                          Resolver
                        </button>
                      </div>
                    )}
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

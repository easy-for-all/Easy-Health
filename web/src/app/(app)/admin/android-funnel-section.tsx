"use client";

// "Funil Android Externo" — where external Android installations stop before an
// account exists. ADMIN ONLY.
//
// Every step counts distinct installation_id, never events, and only builds that
// carry the pre-auth instrumentation are in scope. The historical installed base
// stays in the "App Android" block above and is deliberately not mixed in here:
// older builds never emitted auth_screen_viewed or signup_selected, so counting
// them would report abandonment of a step that could not be reached.
//
// The block describes WHERE people stop. It never claims to know why.
import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import { PillGroup } from "./pill-group";
import { formatCount, formatDateTime } from "./android-installations-metrics";
import {
  type AndroidFunnelPayload,
  type FunnelAudience,
  type FunnelInstallationsPayload,
  type FunnelPeriod,
  type FunnelStepRow,
  type StageBucket,
  AUDIENCE_OPTIONS,
  PERIOD_OPTIONS,
  formatConversion,
  funnelQuery,
  shortInstallationId,
} from "./android-funnel-metrics";

function FilterRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="mb-1 text-[11px] font-medium uppercase tracking-wide text-[var(--text-dim)]">{label}</p>
      {children}
    </div>
  );
}

function StepRow({ step, isFirst }: { step: FunnelStepRow; isFirst: boolean }) {
  const isUsers = step.unit === "users";

  return (
    <tr className={isUsers ? "bg-[var(--surface)]" : undefined}>
      <td className="py-1.5 pr-3 text-xs text-[var(--text)]">
        {step.label}
        {isUsers && (
          <span className="ml-1.5 rounded-full bg-[var(--border)] px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wide text-[var(--text-muted)]">
            usuários
          </span>
        )}
      </td>
      <td className="py-1.5 pr-3 text-right text-xs font-semibold text-[var(--text)]">
        {formatCount(step.count)}
      </td>
      <td className="py-1.5 pr-3 text-right text-xs text-[var(--text-muted)]">
        {isFirst || isUsers ? "—" : formatConversion(step.conversion_from_previous)}
      </td>
      <td className="py-1.5 text-right text-xs text-[var(--text-muted)]">
        {isFirst || isUsers ? "—" : formatConversion(step.conversion_from_cohort)}
      </td>
    </tr>
  );
}

// O desfecho de quem parou no cliente, separado por natureza. Sem isto o painel
// contava um cancelamento voluntário como erro — e o erro real ficava diluído.
function AuthClientOutcomes({ outcomes }: { outcomes: StageBucket[] }) {
  if (!outcomes || outcomes.length === 0) return null;

  return (
    <ul className="ml-3 flex flex-wrap gap-x-4 gap-y-1 border-l border-[var(--border)] pl-3 text-[11px] text-[var(--text-muted)]">
      {outcomes.map((outcome) => (
        <li key={outcome.key}>
          {outcome.label}: <span className="font-semibold text-[var(--text)]">{formatCount(outcome.count)}</span>
        </li>
      ))}
    </ul>
  );
}

function BucketDetails({
  bucket,
  query,
}: {
  bucket: { key: string; label: string; count: number };
  query: string;
}) {
  const [rows, setRows] = useState<FunnelInstallationsPayload | null>(null);
  const [loading, setLoading] = useState(false);

  // Lazy on purpose: opening the panel is the only reason to pay for the list.
  async function load(event: React.SyntheticEvent<HTMLDetailsElement>) {
    if (!event.currentTarget.open || rows || loading) return;
    setLoading(true);
    try {
      setRows(
        await api.get<FunnelInstallationsPayload>(
          `/api/v1/admin/analytics/android_funnel/installations?stage=${bucket.key}&${query}`,
        ),
      );
    } catch {
      setRows(null);
    } finally {
      setLoading(false);
    }
  }

  return (
    <details className="rounded-xl border border-[var(--border)] bg-[var(--bg)] p-2" onToggle={load}>
      <summary className="cursor-pointer text-xs text-[var(--text)]">
        {bucket.label} <span className="font-semibold">({formatCount(bucket.count)})</span>
      </summary>

      {loading && <p className="mt-2 text-[11px] text-[var(--text-dim)]">Carregando…</p>}

      {rows && rows.installations.length === 0 && !loading && (
        <p className="mt-2 text-[11px] text-[var(--text-dim)]">Nenhuma instalação nesta etapa.</p>
      )}

      {rows && rows.installations.length > 0 && (
        <div className="mt-2 overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="text-left text-[10px] text-[var(--text-dim)]">
                <th className="py-1 pr-3 font-medium">Instalação</th>
                <th className="py-1 pr-3 font-medium">Aparelho</th>
                <th className="py-1 pr-3 font-medium">Build</th>
                <th className="py-1 pr-3 font-medium">Último evento</th>
                <th className="py-1 pr-3 font-medium">Visto por último</th>
                <th className="py-1 font-medium">Vínculo</th>
              </tr>
            </thead>
            <tbody>
              {rows.installations.map((row) => (
                <tr key={row.installation_id} className="border-t border-[var(--border)]">
                  <td className="py-1 pr-3">
                    <a
                      href={`/admin/observability?installation_id=${encodeURIComponent(row.installation_id)}`}
                      className="text-primary-600 underline"
                    >
                      {shortInstallationId(row.installation_id)}
                    </a>
                    {row.email && <span className="ml-1 text-[var(--text-dim)]">· {row.email}</span>}
                  </td>
                  <td className="py-1 pr-3 text-[var(--text-muted)]">
                    {[row.device_manufacturer, row.device_model].filter(Boolean).join(" ") || "—"}
                    {row.operating_system_version ? ` · Android ${row.operating_system_version}` : ""}
                  </td>
                  <td className="py-1 pr-3 text-[var(--text-muted)]">
                    {row.app_version ?? "—"} ({row.app_build ?? "—"})
                  </td>
                  <td className="py-1 pr-3 text-[var(--text-muted)]">{row.last_event_name ?? "—"}</td>
                  <td className="py-1 pr-3 text-[var(--text-muted)]">{formatDateTime(row.last_seen_at)}</td>
                  <td className="py-1 text-[var(--text-muted)]">{row.link_result ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {rows.total > rows.installations.length && (
            <p className="mt-1 text-[10px] text-[var(--text-dim)]">
              Mostrando {rows.installations.length} de {formatCount(rows.total)}.
            </p>
          )}
        </div>
      )}
    </details>
  );
}

export function AndroidFunnelSection() {
  const [period, setPeriod] = useState<FunnelPeriod>("since_instrumentation");
  const [audience, setAudience] = useState<FunnelAudience>("external");
  const [build, setBuild] = useState("");
  const [data, setData] = useState<AndroidFunnelPayload | null>(null);
  const [error, setError] = useState(false);

  const query = funnelQuery({ period, build, audience });

  // Only the resolved request writes state: a setState in the body of an effect
  // triggers a cascading render (react-hooks/set-state-in-effect). The `active`
  // guard drops the response of a filter the operator already moved away from.
  useEffect(() => {
    let active = true;

    api
      .get<AndroidFunnelPayload>(`/api/v1/admin/analytics/android_funnel?${query}`)
      .then((next) => {
        if (!active) return;
        setData(next);
        setError(false);
      })
      .catch(() => active && setError(true));

    return () => {
      active = false;
    };
  }, [query]);

  if (error) {
    return (
      <section>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">
          Funil Android Externo
        </h2>
        <p className="text-xs text-[var(--text-dim)]">Funil indisponível no momento.</p>
      </section>
    );
  }

  if (!data) return null;

  const buildOptions = [
    { value: "", label: `Todos (≥ ${data.definitions.min_instrumented_build})` },
    ...data.available_builds.map((value) => ({ value: String(value), label: String(value) })),
  ];

  return (
    <section>
      <h2 className="mb-1 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">
        Funil Android Externo
      </h2>
      <p className="mb-3 text-[11px] leading-snug text-[var(--text-dim)]">
        {data.definitions.instrumentation_note} {data.definitions.unit_note}
      </p>

      <div className="mb-3 space-y-2">
        <FilterRow label="Período">
          <PillGroup value={period} options={PERIOD_OPTIONS} onChange={setPeriod} />
        </FilterRow>
        <FilterRow label="Build">
          <PillGroup value={build} options={buildOptions} onChange={setBuild} />
        </FilterRow>
        <FilterRow label="Público">
          <PillGroup value={audience} options={AUDIENCE_OPTIONS} onChange={setAudience} />
        </FilterRow>
      </div>

      <div className="mb-4 rounded-xl border border-[var(--border)] bg-[var(--bg)] p-3">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-[var(--text-dim)]">
                <th className="py-1.5 pr-3 font-medium">Etapa</th>
                <th className="py-1.5 pr-3 text-right font-medium">Quantidade</th>
                <th className="py-1.5 pr-3 text-right font-medium">% etapa anterior</th>
                <th className="py-1.5 text-right font-medium">% da coorte</th>
              </tr>
            </thead>
            <tbody>
              {data.steps.map((step, index) => (
                <StepRow key={step.key} step={step} isFirst={index === 0} />
              ))}
            </tbody>
          </table>
        </div>
        {data.cohort.excluded.missing_or_invalid_build > 0 && (
          <p className="mt-2 text-[10px] text-[var(--text-dim)]">
            {formatCount(data.cohort.excluded.missing_or_invalid_build)} instalação(ões) fora do funil
            por build ausente ou inválido.
          </p>
        )}
      </div>

      <div className="mb-4 rounded-xl border border-[var(--border)] bg-[var(--bg)] p-3">
        <p className="mb-2 text-[10px] font-semibold uppercase tracking-wide text-[var(--text-dim)]">
          Maior abandono observado
        </p>
        {data.biggest_drop ? (
          <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
            <p className="text-sm font-semibold text-[var(--text)]">
              {data.biggest_drop.from_label} → {data.biggest_drop.to_label}
            </p>
            <p className="text-xs text-[var(--text-muted)]">
              {formatCount(data.biggest_drop.lost)} instalações não avançaram ·{" "}
              {formatConversion(data.biggest_drop.drop_rate)} de abandono
            </p>
          </div>
        ) : (
          <p className="text-xs text-[var(--text-dim)]">Sem dados suficientes para apontar uma queda.</p>
        )}
      </div>

      <div className="rounded-xl border border-[var(--border)] bg-[var(--bg)] p-3">
        <p className="mb-2 text-[10px] font-semibold uppercase tracking-wide text-[var(--text-dim)]">
          Instalações por última etapa
        </p>
        <div className="space-y-1.5">
          {data.stage_buckets.map((bucket) => (
            <div key={bucket.key} className="space-y-1">
              <BucketDetails bucket={bucket} query={query} />
              {/* Só neste bucket: "não chegou à API" juntava uma decisão do
                  usuário, um defeito no aparelho e um sumiço sem desfecho.
                  Rótulos vêm do servidor, como todo o resto do bloco. */}
              {bucket.key === "stopped_auth_client" && (
                <AuthClientOutcomes outcomes={data.stopped_auth_client_breakdown} />
              )}
            </div>
          ))}
        </div>
        <p className="mt-2 text-[10px] leading-snug text-[var(--text-dim)]">
          {data.definitions.conflict_note}
        </p>
        <p className="mt-1 text-[10px] leading-snug text-[var(--text-dim)]">
          {data.definitions.anonymous_classification_note}
        </p>
      </div>
    </section>
  );
}

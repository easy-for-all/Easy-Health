"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { api } from "@/shared/lib/api";
import {
  DEFAULT_PERIOD,
  PERIOD_OPTIONS,
  channelLabel,
  formatCount,
  formatDateTime,
  formatInterval,
  formatRate,
  formatRateDetail,
  isDeferrable,
  makeStatusLabel,
  makeStatusTone,
  originLabel,
  pushStatusLabel,
  pushStatusTone,
  schedulerLabel,
  schedulerStatusLabel,
  schedulerTone,
  warningTone,
  type EventOrchestration,
  type Tone,
} from "./metrics";

const TONE_CLASSES: Record<Tone, string> = {
  ok: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-200",
  warn: "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-200",
  bad: "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-200",
  muted: "bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-300",
};

function Badge({ tone, children }: { tone: Tone; children: React.ReactNode }) {
  return (
    <span className={`inline-block rounded-full px-2 py-0.5 text-xs font-semibold ${TONE_CLASSES[tone]}`}>
      {children}
    </span>
  );
}

function Card({ label, value, description }: { label: string; value: string; description?: string }) {
  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <p className="text-2xl font-bold text-primary-600">{value}</p>
      <p className="mt-1 text-sm font-semibold text-[var(--text)]">{label}</p>
      {description && <p className="mt-0.5 text-xs text-[var(--text-dim)]">{description}</p>}
    </div>
  );
}

function SectionTitle({ title, subtitle }: { title: string; subtitle: string }) {
  return (
    <div>
      <h2 className="text-xs font-bold uppercase tracking-wide text-[var(--text-muted)]">{title}</h2>
      <p className="mt-1 text-xs text-[var(--text-dim)]">{subtitle}</p>
    </div>
  );
}

// Wide tables scroll inside their own box so the page body never scrolls
// sideways on a phone.
function TableShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="overflow-x-auto rounded-2xl border border-[var(--border)] bg-[var(--surface)]">
      <table className="w-full min-w-[640px] text-left text-sm">{children}</table>
    </div>
  );
}

const TH = "px-3 py-2 text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]";
const TD = "px-3 py-2 text-[var(--text)]";

export default function EventsCommunicationsPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();

  const [period, setPeriod] = useState<string>(DEFAULT_PERIOD);
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [data, setData] = useState<EventOrchestration | null>(null);
  const [error, setError] = useState("");
  const [loadedQuery, setLoadedQuery] = useState<string | null>(null);

  // A custom range only becomes a request once both ends are filled, so typing
  // a date does not fire a query per keystroke.
  const query = useMemo(() => {
    const params = new URLSearchParams();
    if (period === "custom") {
      if (!from || !to) return null;
      params.set("from", from);
      params.set("to", to);
    } else {
      params.set("period", period);
    }
    return params.toString();
  }, [period, from, to]);

  const loading = query !== null && loadedQuery !== query;

  useEffect(() => {
    if (authLoading) return;
    if (!user?.admin) {
      router.replace("/");
      return;
    }
    if (query === null) return;

    let cancelled = false;
    api
      .get<EventOrchestration>(`/api/v1/admin/analytics/event_orchestration?${query}`)
      .then((payload) => {
        if (cancelled) return;
        setData(payload);
        setError("");
      })
      .catch(() => {
        if (!cancelled) setError("Erro ao carregar eventos e comunicações.");
      })
      .finally(() => {
        if (!cancelled) setLoadedQuery(query);
      });

    return () => {
      cancelled = true;
    };
  }, [authLoading, user, router, query]);

  if (authLoading || (loading && !data)) return <LoadingScreen />;
  if (!user?.admin) return null;

  const summary = data?.summary;
  const dispatch = data?.push_dispatch_results;

  return (
    <div className="min-h-screen bg-[var(--bg)] px-4 py-6">
      <div className="mx-auto flex max-w-6xl flex-col gap-6">
        <header className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-xl font-bold text-[var(--text)]">Eventos &amp; Comunicações</h1>
            <p className="mt-1 text-xs text-[var(--text-dim)]">
              A EasyHealth produz o fato, o Make decide a comunicação, o backend aplica os hard gates.
            </p>
          </div>
          <Link href="/admin" className="text-sm font-semibold text-primary-600">
            Voltar
          </Link>
        </header>

        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1">
            <span className="text-xs font-semibold text-[var(--text-muted)]">Período</span>
            <select
              value={period}
              onChange={(event) => setPeriod(event.target.value)}
              className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)]"
            >
              {PERIOD_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>
          {period === "custom" && (
            <>
              <label className="flex flex-col gap-1">
                <span className="text-xs font-semibold text-[var(--text-muted)]">De</span>
                <input
                  type="date"
                  value={from}
                  onChange={(event) => setFrom(event.target.value)}
                  className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)]"
                />
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-xs font-semibold text-[var(--text-muted)]">Até</span>
                <input
                  type="date"
                  value={to}
                  onChange={(event) => setTo(event.target.value)}
                  className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)]"
                />
              </label>
            </>
          )}
          {query === null && (
            <p className="text-xs text-[var(--text-dim)]">Preencha as duas datas.</p>
          )}
        </div>

        {error && (
          <p className="rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-200">
            {error}
          </p>
        )}

        {data?.warnings?.length ? (
          <section className="flex flex-col gap-2">
            <SectionTitle title="Alertas" subtitle="O que exige ação agora." />
            {data.warnings.map((warning) => (
              <div
                key={`${warning.code}-${warning.message}`}
                className="flex flex-wrap items-center gap-2 rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-3"
              >
                <Badge tone={warningTone(warning.severity)}>{warning.code}</Badge>
                <span className="text-sm text-[var(--text)]">{warning.message}</span>
              </div>
            ))}
          </section>
        ) : null}

        <section className="flex flex-col gap-3">
          <SectionTitle
            title="Funil de orquestração"
            subtitle="Evento gerado → enviado ao Make → aceito pelo Make. Só eventos do catálogo entram aqui."
          />
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <Card label="Eventos gerados" value={formatCount(summary?.events_generated)} />
            <Card
              label="Enviados ao Make"
              value={formatCount(summary?.sent_to_make)}
              description={`${formatRate(summary?.rates.generated_to_sent)} dos gerados`}
            />
            <Card
              label="Aceitos pelo Make"
              value={formatCount(summary?.accepted_by_make)}
              description={`${formatRate(summary?.rates.sent_to_accepted)} dos enviados`}
            />
            <Card
              label="Erros de envio"
              value={formatCount(summary?.failed_make)}
              description="dead_letter ou falha de rede"
            />
          </div>
          <p className="text-xs text-[var(--text-dim)]">
            Usuários únicos no período: {formatCount(summary?.unique_users)} · gerados→enviados{" "}
            {formatRateDetail(summary?.rates.generated_to_sent)}
          </p>
        </section>

        <section className="flex flex-col gap-3">
          <SectionTitle
            title="Por evento"
            subtitle="Cada linha atravessa o pipeline inteiro. O push é correlacionado pelo evento, não pelo campaign_key."
          />
          <TableShell>
            <thead>
              <tr className="border-b border-[var(--border)]">
                <th className={TH}>Evento</th>
                <th className={TH}>Canais candidatos</th>
                <th className={TH}>Gerados</th>
                <th className={TH}>Enviados</th>
                <th className={TH}>Aceitos</th>
                <th className={TH}>Erros</th>
                <th className={TH}>Push pedidos</th>
                <th className={TH}>Provider ok</th>
                <th className={TH}>Provider erro</th>
                <th className={TH}>Push ignorados</th>
                <th className={TH}>Usuários</th>
                <th className={TH}>Último</th>
              </tr>
            </thead>
            <tbody>
              {(data?.by_event ?? []).map((row) => (
                <tr key={row.event_name} className="border-b border-[var(--border)] last:border-0">
                  <td className={`${TD} font-semibold`}>{row.event_name}</td>
                  <td className={TD}>{row.candidate_channels.map(channelLabel).join(" + ") || "—"}</td>
                  <td className={TD}>{formatCount(row.generated)}</td>
                  <td className={TD}>{formatCount(row.sent_to_make)}</td>
                  <td className={TD}>{formatCount(row.accepted_by_make)}</td>
                  <td className={TD}>{formatCount(row.failed_make)}</td>
                  <td className={TD}>{formatCount(row.push_requested)}</td>
                  <td className={TD}>{formatCount(row.provider_accepted)}</td>
                  <td className={TD}>{formatCount(row.provider_rejected)}</td>
                  <td className={TD}>{formatCount(row.push_skipped)}</td>
                  <td className={TD}>{formatCount(row.unique_users)}</td>
                  <td className={TD}>{formatDateTime(row.last_generated_at)}</td>
                </tr>
              ))}
              {!data?.by_event?.length && (
                <tr>
                  <td className={`${TD} text-[var(--text-dim)]`} colSpan={12}>
                    Nenhum evento de orquestração no período.
                  </td>
                </tr>
              )}
            </tbody>
          </TableShell>
        </section>

        <div className="grid gap-6 md:grid-cols-2">
          <section className="flex flex-col gap-3">
            <SectionTitle
              title="Canais candidatos"
              subtitle="Eventos ELEGÍVEIS por canal. Não significa que o Make enviou — envio está no bloco ao lado."
            />
            <TableShell>
              <thead>
                <tr className="border-b border-[var(--border)]">
                  <th className={TH}>Canal</th>
                  <th className={TH}>Eventos candidatos</th>
                  <th className={TH}>Usuários</th>
                  <th className={TH}>Enviados ao Make</th>
                </tr>
              </thead>
              <tbody>
                {(data?.candidate_channels ?? []).map((row) => (
                  <tr key={row.channel} className="border-b border-[var(--border)] last:border-0">
                    <td className={`${TD} font-semibold`}>
                      {channelLabel(row.channel)}{" "}
                      {!row.configured && <Badge tone="muted">sem evento configurado</Badge>}
                    </td>
                    <td className={TD}>{formatCount(row.candidate_events)}</td>
                    <td className={TD}>{formatCount(row.unique_users)}</td>
                    <td className={TD}>{formatCount(row.sent_to_make)}</td>
                  </tr>
                ))}
              </tbody>
            </TableShell>
          </section>

          <section className="flex flex-col gap-3">
            <SectionTitle
              title="Resultado do push"
              subtitle="O que o Make efetivamente pediu e o que o provider fez. Aqui, sim, é envio."
            />
            <div className="grid grid-cols-2 gap-3">
              <Card label="Solicitados" value={formatCount(dispatch?.requested)} />
              <Card
                label="Aceitos pelo provider"
                value={formatCount(dispatch?.provider_accepted)}
                description={`${formatRate(summary?.rates.dispatch_to_provider_accepted)} dos solicitados`}
              />
              <Card label="Rejeitados" value={formatCount(dispatch?.provider_rejected)} />
              <Card
                label="Ignorados"
                value={formatCount(dispatch?.skipped)}
                description={`${formatCount(dispatch?.not_correlated)} sem evento correlacionado`}
              />
            </div>
            <TableShell>
              <thead>
                <tr className="border-b border-[var(--border)]">
                  <th className={TH}>Motivo do skip</th>
                  <th className={TH}>Total</th>
                  <th className={TH}>Reagendável?</th>
                </tr>
              </thead>
              <tbody>
                {(dispatch?.skips ?? []).map((row) => (
                  <tr key={row.skip_reason} className="border-b border-[var(--border)] last:border-0">
                    <td className={`${TD} font-semibold`}>{row.skip_reason}</td>
                    <td className={TD}>{formatCount(row.count)}</td>
                    <td className={TD}>
                      {isDeferrable(row.skip_reason, dispatch?.deferrable_skip_reasons ?? []) ? (
                        <Badge tone="warn">sim, o Make pode reagendar</Badge>
                      ) : (
                        <Badge tone="muted">não</Badge>
                      )}
                    </td>
                  </tr>
                ))}
                {!dispatch?.skips?.length && (
                  <tr>
                    <td className={`${TD} text-[var(--text-dim)]`} colSpan={3}>
                      Nenhum push ignorado no período.
                    </td>
                  </tr>
                )}
              </tbody>
            </TableShell>
          </section>
        </div>

        <section className="flex flex-col gap-3">
          <SectionTitle
            title="Por origem"
            subtitle="Qual superfície PRODUZIU o evento. É outra dimensão que canal — não misturar."
          />
          <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
            {(data?.by_origin ?? []).map((row) => (
              <Card
                key={row.origin_surface}
                label={originLabel(row.origin_surface)}
                value={formatCount(row.events)}
                description={`${formatCount(row.unique_users)} usuários`}
              />
            ))}
          </div>
        </section>

        <section className="flex flex-col gap-3">
          <SectionTitle
            title="Schedulers"
            subtitle="Se um destes parar, os eventos simplesmente não nascem — sem erro e sem fila."
          />
          <TableShell>
            <thead>
              <tr className="border-b border-[var(--border)]">
                <th className={TH}>Processo</th>
                <th className={TH}>Status</th>
                <th className={TH}>Intervalo</th>
                <th className={TH}>Último sucesso</th>
                <th className={TH}>Candidatos</th>
                <th className={TH}>Eventos criados</th>
                <th className={TH}>Falhas seq.</th>
              </tr>
            </thead>
            <tbody>
              {(data?.schedulers ?? []).map((row) => (
                <tr key={row.key} className="border-b border-[var(--border)] last:border-0">
                  <td className={`${TD} font-semibold`}>{schedulerLabel(row.key)}</td>
                  <td className={TD}>
                    <Badge tone={schedulerTone(row)}>{schedulerStatusLabel(row)}</Badge>
                  </td>
                  <td className={TD}>{formatInterval(row.expected_interval_seconds)}</td>
                  <td className={TD}>{formatDateTime(row.last_success_at)}</td>
                  <td className={TD}>{formatCount(row.candidates_found)}</td>
                  <td className={TD}>{formatCount(row.events_created)}</td>
                  <td className={TD}>{formatCount(row.consecutive_failures)}</td>
                </tr>
              ))}
            </tbody>
          </TableShell>
        </section>

        <section className="flex flex-col gap-3">
          <SectionTitle
            title="Eventos recentes"
            subtitle="O caminho completo de um evento: UserEvent → Make → PushDispatch → provider."
          />
          <TableShell>
            <thead>
              <tr className="border-b border-[var(--border)]">
                <th className={TH}>Evento</th>
                <th className={TH}>Nome</th>
                <th className={TH}>Usuário</th>
                <th className={TH}>Origem</th>
                <th className={TH}>Quando</th>
                <th className={TH}>Make</th>
                <th className={TH}>HTTP</th>
                <th className={TH}>Dispatch</th>
                <th className={TH}>Push</th>
                <th className={TH}>Motivo</th>
              </tr>
            </thead>
            <tbody>
              {(data?.recent_events ?? []).map((row) => (
                <tr
                  key={`${row.event_id}-${row.push_dispatch_id ?? "none"}`}
                  className="border-b border-[var(--border)] last:border-0"
                >
                  <td className={`${TD} font-mono text-xs`}>#{row.event_id}</td>
                  <td className={TD}>{row.event_name}</td>
                  <td className={`${TD} font-mono text-xs`}>{row.user_id}</td>
                  <td className={TD}>{originLabel(row.origin_surface)}</td>
                  <td className={TD}>{formatDateTime(row.created_at)}</td>
                  <td className={TD}>
                    <Badge tone={makeStatusTone(row.make_status)}>{makeStatusLabel(row.make_status)}</Badge>
                  </td>
                  <td className={TD}>{row.make_http_status ?? "—"}</td>
                  <td className={`${TD} font-mono text-xs`}>
                    {row.push_dispatch_id ? `#${row.push_dispatch_id}` : "—"}
                  </td>
                  <td className={TD}>
                    <Badge tone={pushStatusTone(row.push_status)}>{pushStatusLabel(row.push_status)}</Badge>
                  </td>
                  <td className={`${TD} text-xs text-[var(--text-dim)]`}>
                    {row.skip_reason || row.make_error || "—"}
                  </td>
                </tr>
              ))}
              {!data?.recent_events?.length && (
                <tr>
                  <td className={`${TD} text-[var(--text-dim)]`} colSpan={10}>
                    Nenhum evento de orquestração no período.
                  </td>
                </tr>
              )}
            </tbody>
          </TableShell>
        </section>

        <p className="text-xs text-[var(--text-dim)]">
          Catálogo ({data?.catalog.orchestration_events.length ?? 0} eventos):{" "}
          {(data?.catalog.orchestration_events ?? []).join(", ") || "—"}
        </p>
      </div>
    </div>
  );
}

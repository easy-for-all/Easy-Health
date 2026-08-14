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
  formatAdsRatio,
  formatBRL,
  formatConversions,
  formatCount,
  formatDateTime,
  formatDay,
  formatMetric,
  syncTone,
  type AndroidAcquisition,
} from "./metrics";

const TONE_CLASSES = {
  ok: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-200",
  warn: "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-200",
  muted: "bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-300",
};

function Card({
  label,
  value,
  description,
}: {
  label: string;
  value: string;
  description?: string;
}) {
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

export default function AndroidAcquisitionPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();

  const [period, setPeriod] = useState<string>(DEFAULT_PERIOD);
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [data, setData] = useState<AndroidAcquisition | null>(null);
  const [error, setError] = useState("");
  // Derived instead of a setState in the effect body: loading is simply "the
  // query on screen is not the one the current data came from".
  const [loadedQuery, setLoadedQuery] = useState<string | null>(null);

  // A custom range only becomes a request once both ends are filled, so typing
  // a date does not fire a query per keystroke.
  const query = useMemo(() => {
    const params = new URLSearchParams({ period });
    if (period === "custom") {
      if (!start || !end) return null;
      params.set("start", start);
      params.set("end", end);
    }
    return params.toString();
  }, [period, start, end]);

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
      .get<AndroidAcquisition>(`/api/v1/admin/analytics/android_acquisition?${query}`)
      .then((payload) => {
        if (cancelled) return;
        setData(payload);
        setError("");
      })
      .catch(() => {
        if (!cancelled) setError("Erro ao carregar a aquisição Android.");
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

  const ads = data?.ads;
  const eh = data?.easyhealth;
  const sync = data?.sync;
  const tone = sync ? syncTone(sync.status) : "muted";

  return (
    <div className="min-h-screen bg-[var(--bg)] px-4 py-8">
      <div className="mx-auto max-w-6xl space-y-6">
        <header className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <Link href="/admin" className="text-sm font-medium text-primary-600 hover:text-primary-700">
              Voltar
            </Link>
            <h1 className="mt-2 text-xl font-bold text-[var(--text)]">Aquisição Android</h1>
            {data && (
              <p className="mt-1 text-xs text-[var(--text-dim)]">
                {data.filters.start_date} a {data.filters.end_date} · fuso {data.definitions.timezone}
              </p>
            )}
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <div className="flex rounded-lg border border-[var(--border)] bg-[var(--surface)] p-1">
              {PERIOD_OPTIONS.map((item) => (
                <button
                  key={item.value}
                  onClick={() => setPeriod(item.value)}
                  className={`h-9 rounded-md px-3 text-xs font-semibold transition-colors ${
                    period === item.value
                      ? "bg-primary-500 text-white"
                      : "text-[var(--text-muted)] hover:text-[var(--text)]"
                  }`}
                >
                  {item.label}
                </button>
              ))}
            </div>
            {period === "custom" && (
              <div className="flex items-center gap-2">
                <input
                  type="date"
                  value={start}
                  onChange={(e) => setStart(e.target.value)}
                  className="h-9 rounded-lg border border-[var(--border)] bg-[var(--surface)] px-2 text-xs text-[var(--text)]"
                />
                <span className="text-xs text-[var(--text-dim)]">até</span>
                <input
                  type="date"
                  value={end}
                  onChange={(e) => setEnd(e.target.value)}
                  className="h-9 rounded-lg border border-[var(--border)] bg-[var(--surface)] px-2 text-xs text-[var(--text)]"
                />
              </div>
            )}
          </div>
        </header>

        {error && (
          <p className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-200">
            {error}
          </p>
        )}

        {sync && (
          <div className="flex flex-wrap items-center gap-3 rounded-xl border border-[var(--border)] bg-[var(--surface)] p-3">
            <span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${TONE_CLASSES[tone]}`}>
              {sync.label}
            </span>
            <span className="text-xs text-[var(--text-muted)]">
              Última sincronização Google Ads: {formatDateTime(sync.last_synced_at)}
            </span>
            {sync.campaign_id && (
              <span className="text-xs text-[var(--text-dim)]">campanha {sync.campaign_id}</span>
            )}
            {sync.status === "error" && sync.last_error_code && (
              <span className="text-xs text-[var(--text-dim)]">
                erro {sync.last_error_code} em {formatDateTime(sync.last_failed_at)}
              </span>
            )}
            {sync.missing_configuration.length > 0 && (
              <span className="text-xs text-[var(--text-dim)]">
                faltando: {sync.missing_configuration.join(", ")}
              </span>
            )}
          </div>
        )}

        {data && ads && (
          <section className="space-y-3">
            <SectionTitle
              title="Google Ads — campanha Android"
              subtitle={data.definitions.ads_note}
            />
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <Card label="Gasto" value={formatBRL(ads.cost_brl)} />
              <Card label="Instalações atribuídas" value={formatConversions(ads.installs)} />
              <Card label="CPI" value={formatBRL(ads.cpi_brl)} description="Gasto ÷ instalações atribuídas" />
              <Card label="Cadastros atribuídos" value={formatConversions(ads.sign_ups)} />
              <Card label="CPA cadastro" value={formatBRL(ads.cpa_signup_brl)} description="Gasto ÷ cadastros atribuídos" />
              <Card
                label="Instalação → cadastro"
                value={formatAdsRatio(ads.install_to_signup)}
                description="Somente dentro do Google Ads"
              />
              <Card label="Impressões" value={formatCount(ads.impressions)} />
              <Card label="Cliques" value={formatCount(ads.clicks)} />
            </div>
          </section>
        )}

        {data && eh && (
          <section className="space-y-3">
            <SectionTitle title="EasyHealth — uso real" subtitle={data.definitions.product_note} />
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <Card label="Contas Android" value={formatCount(eh.accounts)} />
              <Card label="Criaram treino" value={formatCount(eh.created_workout)} />
              <Card label="Iniciaram treino" value={formatCount(eh.started_workout)} />
              <Card label="Concluíram treino" value={formatCount(eh.completed_workout)} />
              <Card label="Conta → criou treino" value={formatMetric(eh.account_to_created)} />
              <Card label="Criou → iniciou" value={formatMetric(eh.created_to_started)} />
              <Card label="Iniciou → concluiu" value={formatMetric(eh.started_to_completed)} />
              {eh.cohort_maturity === "immature" && (
                <Card
                  label="Coorte recente"
                  value="parcial"
                  description={`Contas criadas há menos de ${data.definitions.cohort_maturity_days} dia ainda podem treinar depois.`}
                />
              )}
            </div>
            <p className="text-xs text-[var(--text-dim)]">{data.definitions.cohort_note}</p>
            <p className="text-xs text-[var(--text-dim)]">{data.definitions.started_note}</p>
          </section>
        )}

        {data && (
          <section className="space-y-3">
            <h2 className="text-xs font-bold uppercase tracking-wide text-[var(--text-muted)]">
              Dia a dia
            </h2>
            <div className="overflow-x-auto rounded-xl border border-[var(--border)] bg-[var(--surface)]">
              <table className="w-full min-w-[900px] text-sm">
                <thead className="border-b border-[var(--border)] text-xs uppercase tracking-wide text-[var(--text-muted)]">
                  <tr>
                    <th className="px-3 py-2 text-left">Data</th>
                    <th className="px-3 py-2 text-right">Gasto Ads</th>
                    <th className="px-3 py-2 text-right">Instalações Ads</th>
                    <th className="px-3 py-2 text-right">CPI</th>
                    <th className="px-3 py-2 text-right">sign_up Ads</th>
                    <th className="px-3 py-2 text-right">CPA signup</th>
                    <th className="px-3 py-2 text-right">Contas Android EH</th>
                    <th className="px-3 py-2 text-right">Criaram treino</th>
                    <th className="px-3 py-2 text-right">Iniciaram</th>
                    <th className="px-3 py-2 text-right">Concluíram</th>
                  </tr>
                </thead>
                <tbody>
                  {data.daily.length === 0 && (
                    <tr>
                      <td colSpan={10} className="px-3 py-6 text-center text-xs text-[var(--text-dim)]">
                        Nenhum dado no período.
                      </td>
                    </tr>
                  )}
                  {data.daily.map((row) => (
                    <tr key={row.date} className="border-b border-[var(--border)] last:border-0">
                      <td className="px-3 py-2 text-left font-medium text-[var(--text)]">
                        {formatDay(row.date)}
                      </td>
                      <td className="px-3 py-2 text-right">{formatBRL(row.ads?.cost_brl)}</td>
                      <td className="px-3 py-2 text-right">{formatConversions(row.ads?.installs)}</td>
                      <td className="px-3 py-2 text-right">{formatBRL(row.ads?.cpi_brl ?? null)}</td>
                      <td className="px-3 py-2 text-right">{formatConversions(row.ads?.sign_ups)}</td>
                      <td className="px-3 py-2 text-right">{formatBRL(row.ads?.cpa_signup_brl ?? null)}</td>
                      <td className="px-3 py-2 text-right">{formatCount(row.easyhealth.accounts)}</td>
                      <td className="px-3 py-2 text-right">{formatCount(row.easyhealth.created_workout)}</td>
                      <td className="px-3 py-2 text-right">{formatCount(row.easyhealth.started_workout)}</td>
                      <td className="px-3 py-2 text-right">{formatCount(row.easyhealth.completed_workout)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        )}

        {data && (
          <footer className="space-y-1 rounded-xl border border-[var(--border)] bg-[var(--surface)] p-4 text-xs text-[var(--text-dim)]">
            <p>{data.definitions.ads_note}</p>
            <p>{data.definitions.product_note}</p>
            <p>{data.definitions.comparison_note}</p>
            <p>{data.definitions.no_cross_rate_note}</p>
            {eh?.data_quality && eh.data_quality.completed_without_started > 0 && (
              <p>
                {eh.data_quality.completed_without_started} conta(s) concluíram treino sem sessão com
                started_at — sessões antigas registradas já concluídas.
              </p>
            )}
          </footer>
        )}
      </div>
    </div>
  );
}

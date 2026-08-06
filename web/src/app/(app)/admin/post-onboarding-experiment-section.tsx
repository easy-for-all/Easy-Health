"use client";

import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import { PillGroup } from "./pill-group";
import { formatCount, formatDateTime } from "./android-installations-metrics";
import {
  AUDIENCE_OPTIONS,
  PERIOD_OPTIONS,
  VARIANT_KEYS,
  VARIANT_OPTIONS,
  experimentQuery,
  formatDifference,
  formatMetricValue,
  formatMetricWithCounts,
  formatRelative,
  formatSeconds,
  hasBlockingDataIssue,
  isTiming,
  type ExperimentAudience,
  type ExperimentPayload,
  type ExperimentPeriod,
  type MetricScopes,
  type VariantFilter,
} from "./post-onboarding-experiment-metrics";

// EXPERIMENTO ANDROID — CONTA APÓS O ONBOARDING.
//
// Duas colunas de variante lado a lado e um funil por variante, porque os
// caminhos são genuinamente diferentes: em account_gate a conta vem antes do
// plano, em open_app vem depois — ou nunca. Forçar as duas num funil sequencial
// único inventaria etapas que uma delas não atravessa.
export function PostOnboardingExperimentSection() {
  const [period, setPeriod] = useState<ExperimentPeriod>("since_start");
  const [audience, setAudience] = useState<ExperimentAudience>("external");
  const [variant, setVariant] = useState<VariantFilter>("all");
  const [build, setBuild] = useState("");
  const [data, setData] = useState<ExperimentPayload | null>(null);
  const [error, setError] = useState(false);

  const query = experimentQuery({ period, build, audience, variant });

  useEffect(() => {
    let active = true;

    api
      .get<ExperimentPayload>(`/api/v1/admin/analytics/post_onboarding_experiment?${query}`)
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
      <section className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-4">
        <h2 className="text-sm font-bold">Experimento Android — conta após o onboarding</h2>
        <p className="mt-2 text-xs text-[var(--text-muted)]">Painel indisponível no momento.</p>
      </section>
    );
  }

  if (!data) {
    return (
      <section className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-4">
        <h2 className="text-sm font-bold">Experimento Android — conta após o onboarding</h2>
        <p className="mt-2 text-xs text-[var(--text-muted)]">Carregando…</p>
      </section>
    );
  }

  const { header, guardrails } = data;

  return (
    <section className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-sm font-bold">Experimento Android — conta após o onboarding</h2>
        <span className="text-[10px] text-[var(--text-dim)]">
          {data.experiment_key} · {formatDateTime(data.generated_at)}
        </span>
      </div>

      {/* No topo de propósito: se este aviso aparece, nenhum número abaixo
          descreve uma população que dá para reconstruir. */}
      {hasBlockingDataIssue(guardrails) && (
        <p className="mt-2 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-[11px] text-amber-600">
          Qualidade de dados: {guardrails.events_missing_installation_id} evento(s) sem installation_id
          {guardrails.variant_disagreement > 0 &&
            ` · ${guardrails.variant_disagreement} instalação(ões) com mais de uma variante`}
          . Enquanto for maior que zero, os números abaixo são leitura parcial.
        </p>
      )}

      <div className="mt-3 flex flex-wrap gap-3">
        <PillGroup value={period} options={PERIOD_OPTIONS} onChange={setPeriod} />
        <PillGroup value={audience} options={AUDIENCE_OPTIONS} onChange={setAudience} />
        <PillGroup value={variant} options={VARIANT_OPTIONS} onChange={setVariant} />
        <input
          value={build}
          onChange={(e) => setBuild(e.target.value.replace(/\D/g, ""))}
          placeholder="build"
          aria-label="Filtrar por build"
          className="w-20 rounded-full border border-[var(--border)] bg-[var(--surface)] px-2.5 py-1 text-xs"
        />
      </div>

      {/* Cabeçalho: quem entrou, quem foi realmente exposto, e como ficou o split. */}
      <dl className="mt-4 grid grid-cols-2 gap-3 text-xs sm:grid-cols-4">
        <Stat label="Status" value={header.status} />
        <Stat label="Build mínimo" value={header.min_build > 0 ? String(header.min_build) : "sem corte"} />
        <Stat label="Início" value={header.started_at ? formatDateTime(header.started_at) : "não definido"} />
        <Stat label="Split esperado" value={header.expected_split} />
        <Stat label="Atribuídas" value={formatCount(header.assigned_installations)} />
        <Stat label="Expostas" value={formatCount(header.exposed_installations)} />
        <Stat
          label="Atribuída sem exposição"
          value={formatMetricValue(header.assigned_without_exposure)}
          hint="Recebeu variante e não chegou ao fim do onboarding"
        />
      </dl>

      <div className="mt-3 grid gap-2 sm:grid-cols-2">
        {header.distribution.map((row) => (
          <div key={row.variant} className="rounded-lg border border-[var(--border)] px-3 py-2">
            <p className="text-xs font-bold">{row.label}</p>
            <p className="text-[11px] text-[var(--text-muted)]">
              {formatCount(row.exposed)} expostas · {formatMetricValue(row.share)} do total
            </p>
            <p className="mt-1 text-[10px] text-[var(--text-dim)]">{row.sample_warning}</p>
          </div>
        ))}
      </div>

      <MetricsTable data={data} />

      <div className="mt-5 grid gap-4 lg:grid-cols-2">
        {data.funnels.map((funnel) => (
          <div key={funnel.variant} className="rounded-lg border border-[var(--border)] p-3">
            <p className="text-xs font-bold">{funnel.label}</p>
            <p className="text-[10px] text-[var(--text-dim)]">
              {formatCount(funnel.exposed)} expostas · {funnel.sample_warning}
            </p>
            <table className="mt-2 w-full text-[11px]">
              <tbody>
                {funnel.stages.map((stage) => (
                  <tr key={stage.key} className="border-t border-[var(--border)]/50">
                    <td className="py-1 pr-2">{stage.label}</td>
                    <td className="py-1 pr-2 text-right tabular-nums">{formatCount(stage.count)}</td>
                    <td className="py-1 text-right tabular-nums text-[var(--text-muted)]">
                      {formatMetricValue(stage.conversion_from_exposed)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ))}
      </div>

      <div className="mt-5 grid gap-4 lg:grid-cols-2">
        {data.last_stage.map((row) => (
          <div key={row.variant} className="rounded-lg border border-[var(--border)] p-3">
            <p className="text-xs font-bold">Última etapa — {row.label}</p>
            <table className="mt-2 w-full text-[11px]">
              <tbody>
                {row.buckets.map((bucket) => (
                  <tr key={bucket.key} className="border-t border-[var(--border)]/50">
                    <td className="py-1 pr-2">{bucket.label}</td>
                    <td className="py-1 text-right tabular-nums">{formatCount(bucket.count)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ))}
      </div>

      <GuardrailsBlock data={data} />

      <p className="mt-4 text-[10px] leading-relaxed text-[var(--text-dim)]">
        {data.definitions.unit_note} {data.definitions.window_note} {data.definitions.readout_note}
      </p>
    </section>
  );
}

function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div>
      <dt className="text-[10px] uppercase tracking-wide text-[var(--text-dim)]">{label}</dt>
      <dd className="font-bold">{value}</dd>
      {hint && <p className="text-[10px] text-[var(--text-dim)]">{hint}</p>}
    </div>
  );
}

function MetricsTable({ data }: { data: ExperimentPayload }) {
  return (
    <div className="mt-5 overflow-x-auto">
      <table className="w-full text-[11px]">
        <thead>
          <tr className="text-left text-[10px] uppercase tracking-wide text-[var(--text-dim)]">
            <th className="py-1 pr-3">Métrica</th>
            <th className="py-1 pr-3">Conta antes</th>
            <th className="py-1 pr-3">Abre o app</th>
            <th className="py-1 pr-3">Diferença</th>
            <th className="py-1">Relativa</th>
          </tr>
        </thead>
        <tbody>
          {data.metrics.map((row) => {
            const control = row.variants.account_gate;
            const treatment = row.variants.open_app;

            // Tempo até o primeiro treino não é razão: mostrar p50 seria mentir
            // se ficasse na mesma coluna de uma taxa.
            if (control && isTiming(control) && treatment && isTiming(treatment)) {
              return (
                <tr key={row.key} className="border-t border-[var(--border)]/50">
                  <td className="py-1 pr-3">{row.label} (p50)</td>
                  <td className="py-1 pr-3 tabular-nums">{formatSeconds(control.p50_seconds)}</td>
                  <td className="py-1 pr-3 tabular-nums">{formatSeconds(treatment.p50_seconds)}</td>
                  <td className="py-1 pr-3 text-[var(--text-dim)]">—</td>
                  <td className="py-1 text-[var(--text-dim)]">—</td>
                </tr>
              );
            }

            const controlScopes = control as MetricScopes | undefined;
            const treatmentScopes = treatment as MetricScopes | undefined;

            return (
              <tr key={row.key} className="border-t border-[var(--border)]/50">
                <td className="py-1 pr-3">
                  {row.label}
                  {row.note && <span className="block text-[10px] text-[var(--text-dim)]">{row.note}</span>}
                </td>
                <td className="py-1 pr-3 tabular-nums">{formatMetricWithCounts(controlScopes?.cumulative)}</td>
                <td className="py-1 pr-3 tabular-nums">{formatMetricWithCounts(treatmentScopes?.cumulative)}</td>
                <td className="py-1 pr-3 tabular-nums">{formatDifference(row.difference?.cumulative)}</td>
                <td className="py-1 tabular-nums">{formatRelative(row.difference?.cumulative)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function GuardrailsBlock({ data }: { data: ExperimentPayload }) {
  const { guardrails } = data;

  return (
    <details className="mt-5">
      <summary className="cursor-pointer text-xs font-bold">Guardrails</summary>
      <dl className="mt-2 grid grid-cols-2 gap-3 text-[11px] sm:grid-cols-3">
        <Stat label="Eventos sem installation_id" value={formatCount(guardrails.events_missing_installation_id)} />
        <Stat label="Instalação com 2 variantes" value={formatCount(guardrails.variant_disagreement)} />
        <Stat
          label="Erros de geração"
          value={formatCount(guardrails.generation_errors)}
          hint="Lido do servidor, não de eventos do cliente"
        />
        <Stat label="Bateu o limite de 3" value={formatMetricValue(guardrails.hit_limit_rate)} />
        <Stat label="Viu a conta depois" value={formatMetricValue(guardrails.gate_seen_later_rate)} />
        {VARIANT_KEYS.map((key) => (
          <Stat
            key={key}
            label={`Sem plano — ${key === "account_gate" ? "conta antes" : "abre o app"}`}
            value={formatMetricValue(guardrails.no_plan_after_exposure?.[key])}
          />
        ))}
        {VARIANT_KEYS.map((key) => (
          <Stat
            key={`auth-${key}`}
            label={`Falha de auth — ${key === "account_gate" ? "conta antes" : "abre o app"}`}
            value={formatCount(guardrails.auth_failures?.[key])}
          />
        ))}
      </dl>

      {Object.keys(guardrails.claim_failures ?? {}).length > 0 && (
        <p className="mt-2 text-[10px] text-[var(--text-dim)]">
          Conflitos de vínculo:{" "}
          {Object.entries(guardrails.claim_failures)
            .map(([code, count]) => `${code}: ${count}`)
            .join(" · ")}
        </p>
      )}
    </details>
  );
}

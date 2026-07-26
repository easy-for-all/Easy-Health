"use client";

// "App Android" — the real installed base from app_installations. ADMIN ONLY.
//
// The panel keeps three views strictly apart so a number is never read as
// something it is not:
//   - histórico          : every Android installation ever registered.
//   - tracking atual     : builds >= the reconciliation threshold, the only
//                          honest measure of how the current flow is doing.
//   - legado             : older builds, whose anonymous rows are expected.
// Installations ≠ devices ≠ users ≠ sessions ≠ Google Play downloads.
import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import {
  type AndroidInstallationMetrics,
  type ComponentStatus,
  type Metric,
  COMPONENT_STATUS_LABEL,
  HEALTH_STATE_LABEL,
  componentColors,
  displayLabel,
  formatCount,
  formatDate,
  formatDateTime,
  formatRate,
  formatRateWithSample,
  hasDataQualityIssues,
  healthColors,
  healthState,
} from "./android-installations-metrics";

function Stat({ label, value, hint }: { label: string; value: number; hint?: string }) {
  return (
    <div className="rounded-xl border border-[var(--border)] bg-[var(--bg)] p-3" title={hint}>
      <p className="text-2xl font-bold text-primary-600">{formatCount(value)}</p>
      <p className="mt-0.5 text-xs font-semibold text-[var(--text)]">{label}</p>
      {hint && <p className="mt-0.5 text-[10px] leading-snug text-[var(--text-dim)]">{hint}</p>}
    </div>
  );
}

function Group({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-4">
      <p className="mb-2 text-[10px] font-semibold uppercase tracking-wide text-[var(--text-dim)]">{title}</p>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">{children}</div>
    </div>
  );
}

function Block({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return (
    <div className="mb-4 rounded-xl border border-[var(--border)] bg-[var(--bg)] p-3">
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-x-2 gap-y-1">
        <p className="text-xs font-semibold text-[var(--text)]">{title}</p>
        {hint && <p className="text-[10px] text-[var(--text-dim)]">{hint}</p>}
      </div>
      {children}
    </div>
  );
}

function Badge({ label, color, background }: { label: string; color: string; background: string }) {
  return (
    <span
      className="rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
      style={{ color, backgroundColor: background }}
    >
      {label}
    </span>
  );
}

function Mini({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-lg font-bold text-[var(--text)]">{value}</p>
      <p className="text-[10px] text-[var(--text-dim)]">{label}</p>
    </div>
  );
}

function Table({ headers, children }: { headers: string[]; children: React.ReactNode }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-xs text-[var(--text-dim)]">
            {headers.map((header, index) => (
              <th key={header} className={`py-1.5 pr-3 font-medium ${index === 0 ? "" : "text-right"}`}>
                {header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>{children}</tbody>
      </table>
    </div>
  );
}

function Cell({ children, muted, first }: { children: React.ReactNode; muted?: boolean; first?: boolean }) {
  return (
    <td
      className={`py-1.5 pr-3 text-xs ${first ? "" : "text-right"} ${
        muted ? "text-[var(--text-dim)]" : "text-[var(--text)]"
      }`}
    >
      {children}
    </td>
  );
}

function HealthHeadline({ metric, noun }: { metric: Metric; noun: string }) {
  const state = healthState(metric);
  const colors = healthColors(state);

  return (
    <div className="flex flex-wrap items-center gap-2">
      <p className="text-2xl font-bold" style={{ color: colors.color }}>
        {formatRate(metric)}
      </p>
      <Badge label={HEALTH_STATE_LABEL[state]} color={colors.color} background={colors.background} />
      <p className="text-[11px] text-[var(--text-dim)]">{formatRateWithSample(metric, noun)}</p>
    </div>
  );
}

export function AndroidInstallationsSection() {
  const [data, setData] = useState<AndroidInstallationMetrics | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    api
      .get<AndroidInstallationMetrics>("/api/v1/admin/analytics/android_installations")
      .then(setData)
      .catch(() => setError(true));
  }, []);

  const minBuild = data?.definitions.reconciliation_min_build;

  return (
    <section className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <div className="mb-3 flex items-baseline justify-between gap-2">
        <h2 className="text-sm font-bold text-[var(--text)]">App Android</h2>
        <span className="text-[10px] uppercase tracking-wide text-[var(--text-dim)]">base instalada real</span>
      </div>

      {error ? (
        <p className="rounded-xl bg-[var(--hot-soft)] px-3 py-2 text-xs text-[var(--hot)]">
          Não foi possível carregar as métricas de instalação Android.
        </p>
      ) : !data ? (
        <p className="text-xs text-[var(--text-dim)]">Carregando…</p>
      ) : (
        <>
          {/* 1 — Visão geral (histórico completo) */}
          <Group title="Visão geral · histórico">
            <Stat
              label="Instalações Android registradas"
              value={data.overview.total_installations}
              hint="Registros únicos de AppInstallation. Não equivale ao total oficial de downloads da Google Play."
            />
            <Stat
              label="Usuários Android únicos"
              value={data.overview.unique_linked_users}
              hint="Usuários distintos vinculados a alguma instalação. Um usuário pode ter mais de uma."
            />
            <Stat
              label="Instalações vinculadas"
              value={data.overview.linked_installations}
              hint="Instalações com usuário identificado (user_id preenchido)."
            />
            <Stat
              label="Instalações ainda anônimas"
              value={data.overview.anonymous_installations}
              hint="Instalou e ainda não autenticou. Não é necessariamente um erro."
            />
            <Stat
              label="Ativas nos últimos 7 dias"
              value={data.overview.active_installations_7d}
              hint="Instalações com last_seen_at nos últimos 7 dias."
            />
            <Stat
              label="Ativas nos últimos 30 dias"
              value={data.overview.active_installations_30d}
              hint="Instalações com last_seen_at nos últimos 30 dias."
            />
          </Group>

          <p className="mb-4 text-[10px] text-[var(--text-dim)]">
            Taxa de vínculo histórica: {formatRateWithSample(data.overview.link_rate)} ·{" "}
            {formatCount(data.overview.users_with_multiple_installations)} usuário(s) com mais de uma instalação ·{" "}
            {formatCount(data.overview.authenticated_installations)} com autenticação confirmada.
          </p>

          {/* 2 — Saúde do tracking atual */}
          <Block
            title={`Saúde do tracking — build ${minBuild}+`}
            hint="somente builds que enviam o identificador de instalação"
          >
            <HealthHeadline
              metric={data.current_tracking.link_rate}
              noun={`instalações do build ${minBuild}+`}
            />
            <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
              <Mini label="instalações" value={formatCount(data.current_tracking.total_installations)} />
              <Mini label="vinculadas" value={formatCount(data.current_tracking.linked_installations)} />
              <Mini label="anônimas" value={formatCount(data.current_tracking.anonymous_installations)} />
              <Mini
                label="autenticação confirmada"
                value={formatCount(data.current_tracking.authenticated_installations)}
              />
            </div>
          </Block>

          {/* 3 — Legado */}
          <Block title={`Instalações legadas — antes do build ${minBuild}`}>
            <div className="grid grid-cols-3 gap-3">
              <Mini label="instalações" value={formatCount(data.legacy.total_installations)} />
              <Mini label="vinculadas" value={formatCount(data.legacy.linked_installations)} />
              <Mini label="anônimas" value={formatCount(data.legacy.anonymous_installations)} />
            </div>
            <p className="mt-2 text-[10px] leading-snug text-[var(--text-dim)]">
              Builds anteriores ao {minBuild} não enviavam o identificador de instalação em todas as requisições
              autenticadas. Registros anônimos desse grupo não devem ser usados para avaliar a saúde do tracking
              atual.
            </p>
          </Block>

          {/* 4 — Qualidade dos dados */}
          <Block title="Qualidade dos dados">
            {!hasDataQualityIssues(data.data_quality) ? (
              <p className="text-xs text-[var(--text-dim)]">Nenhuma inconsistência detectada.</p>
            ) : (
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                <Mini
                  label="vinculada sem last_authenticated_at"
                  value={formatCount(data.data_quality.linked_without_last_authenticated_at)}
                />
                <Mini
                  label="last_authenticated_at sem usuário"
                  value={formatCount(data.data_quality.authenticated_at_without_user)}
                />
                <Mini label="build ausente" value={formatCount(data.data_quality.missing_app_build)} />
                <Mini label="build inválido" value={formatCount(data.data_quality.invalid_app_build)} />
                <Mini label="versão ausente" value={formatCount(data.data_quality.missing_app_version)} />
                <Mini label="last_seen_at ausente" value={formatCount(data.data_quality.missing_last_seen_at)} />
              </div>
            )}
          </Block>

          {/* 5 — Adoção de versão */}
          <Block title="Adoção de versão" hint="útil logo após cada publicação">
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <Mini label="versão mais usada" value={displayLabel(data.adoption.most_used_version)} />
              <Mini label="build mais usado" value={displayLabel(data.adoption.most_used_build)} />
              <Mini label="último build conhecido" value={displayLabel(data.adoption.latest_build)} />
              <Mini label="no build mais recente" value={formatRate(data.adoption.latest_build_share)} />
            </div>
            <p className="mt-2 text-[10px] text-[var(--text-dim)]">
              {formatRateWithSample(data.adoption.latest_build_share)} já estão no build mais recente.
            </p>
          </Block>

          {/* 6 — Health timeline */}
          <Block
            title="Vínculo por dia"
            hint={`novas instalações nos últimos ${data.definitions.timeline_days} dias`}
          >
            {data.health_timeline.length === 0 ? (
              <p className="text-xs text-[var(--text-dim)]">Nenhuma instalação nova no período.</p>
            ) : (
              <Table headers={["Data", "Novas", "Vinculadas", "Taxa"]}>
                {data.health_timeline.map((row) => (
                  <tr key={row.date} className="border-t border-[var(--border)]">
                    <Cell first>{formatDate(row.date)}</Cell>
                    <Cell>{formatCount(row.new_installations)}</Cell>
                    <Cell>{formatCount(row.linked_installations)}</Cell>
                    <Cell muted>{formatRate(row.link_rate)}</Cell>
                  </tr>
                ))}
              </Table>
            )}
          </Block>

          {/* 7 — Saúde operacional */}
          <Block title="Saúde operacional" hint="derivada apenas de sinais reais">
            <ul className="grid gap-1.5 sm:grid-cols-2">
              {data.operational_health.map((component) => {
                const colors = componentColors(component.status);
                return (
                  <li key={component.key} className="flex items-center gap-2">
                    <span
                      className="h-2 w-2 shrink-0 rounded-full"
                      style={{ backgroundColor: colors.color }}
                      aria-hidden
                    />
                    <span className="text-xs font-semibold text-[var(--text)]">{component.label}</span>
                    <Badge
                      label={COMPONENT_STATUS_LABEL[component.status as ComponentStatus] ?? component.status}
                      color={colors.color}
                      background={colors.background}
                    />
                    <span className="truncate text-[10px] text-[var(--text-dim)]" title={component.detail}>
                      {component.detail}
                    </span>
                  </li>
                );
              })}
            </ul>
          </Block>

          {/* 8 — Versões do app */}
          <Block title="Versões do app" hint="builds numéricos mais recentes primeiro; sem build por último">
            {data.versions.length === 0 ? (
              <p className="text-xs text-[var(--text-dim)]">Nenhuma instalação registrada.</p>
            ) : (
              <Table headers={["Versão", "Build", "Instalações", "Vinculadas", "Anônimas", "Ativas 7d", "Taxa"]}>
                {data.versions.map((row) => (
                  <tr key={`${row.app_version ?? "?"}-${row.app_build ?? "?"}`} className="border-t border-[var(--border)]">
                    <Cell first>
                      {displayLabel(row.app_version)}
                      {row.current_tracking && (
                        <span className="ml-1 text-[9px] uppercase text-[var(--good)]">tracking</span>
                      )}
                    </Cell>
                    <Cell>{displayLabel(row.app_build)}</Cell>
                    <Cell>{formatCount(row.total_installations)}</Cell>
                    <Cell>{formatCount(row.linked_installations)}</Cell>
                    <Cell muted>{formatCount(row.anonymous_installations)}</Cell>
                    <Cell muted>{formatCount(row.active_installations_7d)}</Cell>
                    <Cell muted>{formatRate(row.link_rate)}</Cell>
                  </tr>
                ))}
              </Table>
            )}
          </Block>

          {/* 9 — Dispositivos */}
          <Block title="Dispositivos">
            <div className="grid gap-4 lg:grid-cols-2">
              <div>
                <p className="mb-1 text-[10px] font-semibold uppercase tracking-wide text-[var(--text-dim)]">
                  Fabricantes
                </p>
                {data.manufacturers.length === 0 ? (
                  <p className="text-xs text-[var(--text-dim)]">Sem dados.</p>
                ) : (
                  <Table headers={["Fabricante", "Instalações", "Vinculadas", "Ativas 30d"]}>
                    {data.manufacturers.map((row) => (
                      <tr key={displayLabel(row.manufacturer)} className="border-t border-[var(--border)]">
                        <Cell first>{displayLabel(row.manufacturer)}</Cell>
                        <Cell>{formatCount(row.total_installations)}</Cell>
                        <Cell>{formatCount(row.linked_installations)}</Cell>
                        <Cell muted>{formatCount(row.active_installations_30d)}</Cell>
                      </tr>
                    ))}
                  </Table>
                )}
              </div>

              <div>
                <p className="mb-1 text-[10px] font-semibold uppercase tracking-wide text-[var(--text-dim)]">
                  Modelos
                </p>
                {data.device_models.length === 0 ? (
                  <p className="text-xs text-[var(--text-dim)]">Sem dados.</p>
                ) : (
                  <Table headers={["Modelo", "Instalações", "Ativas 30d"]}>
                    {data.device_models.map((row) => (
                      <tr
                        key={`${displayLabel(row.manufacturer)}-${displayLabel(row.device_model)}`}
                        className="border-t border-[var(--border)]"
                      >
                        <Cell first>
                          <span className="text-[var(--text-dim)]">{displayLabel(row.manufacturer)}</span>{" "}
                          {displayLabel(row.device_model)}
                        </Cell>
                        <Cell>{formatCount(row.total_installations)}</Cell>
                        <Cell muted>{formatCount(row.active_installations_30d)}</Cell>
                      </tr>
                    ))}
                  </Table>
                )}
              </div>
            </div>

            <div className="mt-4">
              <p className="mb-1 text-[10px] font-semibold uppercase tracking-wide text-[var(--text-dim)]">
                Versões do Android
              </p>
              {data.operating_system_versions.length === 0 ? (
                <p className="text-xs text-[var(--text-dim)]">Sem dados.</p>
              ) : (
                <Table headers={["Versão do Android", "Instalações"]}>
                  {data.operating_system_versions.map((row) => (
                    <tr
                      key={displayLabel(row.operating_system_version)}
                      className="border-t border-[var(--border)]"
                    >
                      <Cell first>{displayLabel(row.operating_system_version)}</Cell>
                      <Cell>{formatCount(row.total_installations)}</Cell>
                    </tr>
                  ))}
                </Table>
              )}
            </div>
          </Block>

          {/* 10 — Pipeline de analytics (nunca instalações) */}
          <Block title="Pipeline de analytics" hint="eventos e sessões — não é contagem de instalações">
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <Mini label="eventos Android" value={formatCount(data.analytics_pipeline.android_events_total)} />
              <Mini label="eventos em 7d" value={formatCount(data.analytics_pipeline.android_events_7d)} />
              <Mini
                label="instalações com sessão"
                value={formatCount(data.analytics_pipeline.installations_with_session)}
              />
              <Mini label="último evento" value={formatDateTime(data.analytics_pipeline.last_event_at)} />
            </div>
          </Block>

          {/* 11 — Google Play (ainda não integrado) */}
          <Block title="Google Play" hint={data.google_play.configured ? undefined : "não integrado"}>
            <div className="grid grid-cols-3 gap-3">
              <Mini label="instalações oficiais" value={formatCount(data.google_play.official_installs)} />
              <Mini label="última sincronização" value={formatDateTime(data.google_play.last_synced_at)} />
              <Mini label="origem dos dados" value={displayLabel(data.google_play.source)} />
            </div>
            <p className="mt-2 text-[10px] leading-snug text-[var(--text-dim)]">
              O total oficial de instalações vem da Play Console e ainda não é sincronizado por este painel. Os
              números acima permanecem vazios até essa integração existir.
            </p>
          </Block>

          {/* Funil de usuários + procedência */}
          <Block title="Usuários Android vinculados" hint="cada passo é medido sobre usuários, não instalações">
            <Table headers={["Etapa", "Usuários", "Conversão"]}>
              {data.user_funnel.map((step) => (
                <tr key={step.label} className="border-t border-[var(--border)]">
                  <Cell first>{step.label}</Cell>
                  <Cell>{formatCount(step.count)}</Cell>
                  <Cell muted>{formatRate(step.conversion)}</Cell>
                </tr>
              ))}
            </Table>
          </Block>

          <p className="text-[10px] leading-snug text-[var(--text-dim)]">
            Fonte: app_installations · procedência do registro:{" "}
            {formatCount(data.installation_provenance.registered_live)} vindas do app ao vivo e{" "}
            {formatCount(data.installation_provenance.backfilled)} reconstruídas de device_tokens (
            {formatRate(data.installation_provenance.coverage)} ao vivo). Instalações ≠ dispositivos ≠ usuários ≠
            sessões ≠ downloads da Google Play. Atualizado em {formatDateTime(data.generated_at)}.
          </p>
        </>
      )}
    </section>
  );
}

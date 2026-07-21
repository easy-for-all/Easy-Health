"use client";

// "APP ANDROID" (Fase 23) — the REAL installed base from app_installations,
// which fixes the old Android n=1 (that counted the write-once
// users.activation_platform). ADMIN ONLY. Separates Installations / Devices /
// Users / Sessions so they are never read as the same number.
import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";

interface Metric {
  value: number;
  numerator: number;
  denominator: number;
  status: string;
  definition: string;
}

interface FunnelStep {
  label: string;
  count: number;
  conversion: Metric;
}

interface VersionRow {
  app_version: string;
  installations: number;
  active_7d: number;
  push_enabled: number;
}

interface Payload {
  installations: {
    known: number;
    authenticated: number;
    anonymous: number;
    registered_live: number;
    backfilled: number;
  };
  users: { identified: number };
  activity: { active_today: number; active_7d: number; active_30d: number; new_30d: number };
  push: { permission_granted: number; push_enabled: number; valid_fcm_tokens: number };
  sessions: { with_session: number; events_received: number };
  versions: VersionRow[];
  tracking_coverage: Metric;
  funnel: FunnelStep[];
  source: string;
  generated_at: string;
}

function Stat({ label, value, hint }: { label: string; value: number; hint?: string }) {
  return (
    <div className="rounded-xl border border-[var(--border)] bg-[var(--bg)] p-3">
      <p className="text-2xl font-bold text-primary-600">{value.toLocaleString("pt-BR")}</p>
      <p className="mt-0.5 text-xs font-semibold text-[var(--text)]">{label}</p>
      {hint && <p className="text-[10px] text-[var(--text-dim)]">{hint}</p>}
    </div>
  );
}

function coveragePct(m: Metric): string {
  if (m.status === "no_coverage" || m.denominator === 0) return "—";
  return `${m.value}%`;
}

function Group({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-3">
      <p className="mb-2 text-[10px] font-semibold uppercase tracking-wide text-[var(--text-dim)]">{title}</p>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">{children}</div>
    </div>
  );
}

export function AndroidInstallationsSection() {
  const [data, setData] = useState<Payload | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    api
      .get<Payload>("/api/v1/admin/analytics/android_installations")
      .then(setData)
      .catch(() => setError(true));
  }, []);

  if (error) return null;

  return (
    <section className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <div className="mb-3 flex items-baseline justify-between gap-2">
        <h2 className="text-sm font-bold text-[var(--text)]">App Android</h2>
        <span className="text-[10px] uppercase tracking-wide text-[var(--text-dim)]">base instalada real</span>
      </div>

      {!data ? (
        <p className="text-xs text-[var(--text-dim)]">Carregando…</p>
      ) : (
        <>
          <Group title="Instalações">
            <Stat label="Conhecidas" value={data.installations.known} />
            <Stat label="Autenticadas" value={data.installations.authenticated} />
            <Stat label="Anônimas" value={data.installations.anonymous} />
            <Stat
              label="Rastreadas ao vivo"
              value={data.installations.registered_live}
              hint={`histórico: ${data.installations.backfilled}`}
            />
          </Group>

          <Group title="Usuários · Dispositivos · Sessões">
            <Stat label="Usuários identificados" value={data.users.identified} />
            <Stat label="Push habilitado" value={data.push.push_enabled} hint={`permissão: ${data.push.permission_granted}`} />
            <Stat label="Tokens FCM válidos" value={data.push.valid_fcm_tokens} />
            <Stat label="Eventos recebidos" value={data.sessions.events_received} />
          </Group>

          <Group title="Atividade">
            <Stat label="Ativos hoje" value={data.activity.active_today} />
            <Stat label="Ativos 7d" value={data.activity.active_7d} />
            <Stat label="Ativos 30d" value={data.activity.active_30d} />
            <Stat label="Novas 30d" value={data.activity.new_30d} />
          </Group>

          <div className="mb-3 rounded-xl border border-[var(--border)] bg-[var(--bg)] p-3">
            <div className="flex items-baseline justify-between">
              <p className="text-xs font-semibold text-[var(--text)]">Cobertura do tracking</p>
              <p className="text-lg font-bold text-primary-600">{coveragePct(data.tracking_coverage)}</p>
            </div>
            <p className="text-[10px] text-[var(--text-dim)]">
              instalações rastreadas ao vivo ({data.tracking_coverage.numerator}) / conhecidas ({data.tracking_coverage.denominator}). Cresce à medida que o app atualizado abre.
            </p>
          </div>

          {/* Funnel */}
          <div className="mb-3 overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-[var(--text-dim)]">
                  <th className="py-1.5 pr-3 font-medium">Funil</th>
                  <th className="py-1.5 pr-3 font-medium text-right">Qtd</th>
                  <th className="py-1.5 pr-3 font-medium text-right">Conversão</th>
                </tr>
              </thead>
              <tbody>
                {data.funnel.map((s) => (
                  <tr key={s.label} className="border-t border-[var(--border)]">
                    <td className="py-1.5 pr-3 text-xs text-[var(--text)]">{s.label}</td>
                    <td className="py-1.5 pr-3 text-right text-xs font-semibold text-[var(--text)]">{s.count}</td>
                    <td className="py-1.5 pr-3 text-right text-xs text-[var(--text-dim)]">{coveragePct(s.conversion)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Versions */}
          {data.versions.length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-[var(--text-dim)]">
                    <th className="py-1.5 pr-3 font-medium">Versão</th>
                    <th className="py-1.5 pr-3 font-medium text-right">Instalações</th>
                    <th className="py-1.5 pr-3 font-medium text-right">Ativas 7d</th>
                    <th className="py-1.5 pr-3 font-medium text-right">Push</th>
                  </tr>
                </thead>
                <tbody>
                  {data.versions.map((v) => (
                    <tr key={v.app_version} className="border-t border-[var(--border)]">
                      <td className="py-1.5 pr-3 text-xs text-[var(--text)]">{v.app_version}</td>
                      <td className="py-1.5 pr-3 text-right text-xs text-[var(--text)]">{v.installations}</td>
                      <td className="py-1.5 pr-3 text-right text-xs text-[var(--text-dim)]">{v.active_7d}</td>
                      <td className="py-1.5 pr-3 text-right text-xs text-[var(--text-dim)]">{v.push_enabled}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <p className="mt-3 text-[10px] text-[var(--text-dim)]">
            Fonte: app_installations. Instalações ≠ dispositivos ≠ usuários ≠ sessões.
          </p>
        </>
      )}
    </section>
  );
}

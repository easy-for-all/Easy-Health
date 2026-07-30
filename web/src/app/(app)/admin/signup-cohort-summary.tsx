import { StatCard } from "./stat-card";
import { formatCount, formatRateWithSample, type Metric } from "./android-installations-metrics";

// Cohort summary + Android diagnostic funnel for the Usuários section.
//
// Pure presentation: it takes the numbers the users endpoint already returned for
// the SAME window the table is showing. It deliberately does not fetch on its
// own — a second request could resolve a different window and the panel would
// show a summary of one period beside a list of another.

export type SignupSource = "android" | "web" | "pwa" | "unknown";

export interface CohortSummary {
  total: number;
  by_source: Record<SignupSource, number>;
  reportable_total: number;
  unknown_share: Metric;
}

export interface AndroidFunnel {
  installations_observed: number;
  reached_authentication: Metric;
  users_created_from_android: number;
  linked_installations: Metric;
  anonymous_installations: number;
  auth_attempt_events: Record<string, number>;
}

export interface CohortDefinitions {
  period: string;
  source: string | null;
  timezone: string;
  window_from: string | null;
  window_to: string | null;
  generated_at: string;
  unknown_note: string;
  installations_observed: string;
  reached_authentication: string;
  users_created_from_android: string;
  linked_installations: string;
  anonymous_installations: string;
  auth_attempt_events: string;
}

const ATTEMPT_EVENT_LABELS: Record<string, string> = {
  android_registration_started: "Cadastro Android iniciado",
  android_registration_failed: "Cadastro Android falhou",
  google_auth_started: "Google iniciado",
  google_auth_failed: "Google falhou",
};

function formatWindowBoundary(iso: string | null): string {
  if (!iso) return "—";
  // The backend already resolved these in the reporting zone and kept the
  // offset in the string, so parse-and-format must not re-localize to the
  // viewer's timezone — slice the ISO string instead.
  const [date, time] = iso.split("T");
  const [year, month, day] = date.split("-");
  return `${day}/${month}/${year} ${time?.slice(0, 5) ?? ""}`.trim();
}

function Block({ title, children, note }: { title: string; children: React.ReactNode; note?: string }) {
  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <h3 className="text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">{title}</h3>
      <div className="mt-3">{children}</div>
      {note && <p className="mt-3 text-[11px] leading-relaxed text-[var(--text-dim)]">{note}</p>}
    </div>
  );
}

function FunnelRow({ label, value, detail, definition }: { label: string; value: string; detail?: string; definition: string }) {
  return (
    <div className="border-b border-[var(--border)] py-2 last:border-0">
      <div className="flex items-baseline justify-between gap-4">
        <span className="text-sm text-[var(--text)]">{label}</span>
        <span className="shrink-0 text-lg font-bold text-primary-600">{value}</span>
      </div>
      {detail && <p className="text-[11px] text-[var(--text-muted)]">{detail}</p>}
      <p className="mt-0.5 text-[10px] leading-relaxed text-[var(--text-dim)]">{definition}</p>
    </div>
  );
}

export function SignupCohortSummary({
  summary, funnel, definitions,
}: {
  summary?: CohortSummary;
  funnel?: AndroidFunnel;
  definitions?: CohortDefinitions;
}) {
  if (!summary || !funnel || !definitions) return null;

  const allTime = !definitions.window_from;
  const windowLabel = allTime
    ? "Desde sempre (sem corte de período)"
    : `${formatWindowBoundary(definitions.window_from)} → ${formatWindowBoundary(definitions.window_to)} · ${definitions.timezone}`;

  return (
    <div className="mb-4 space-y-3">
      <Block title="Novos usuários no período">
        <p className="-mt-1 mb-3 text-[11px] text-[var(--text-muted)]">
          Janela de <strong>criação da conta</strong>: {windowLabel}
        </p>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          <StatCard
            label="Novos usuários"
            value={summary.total}
            description={`${formatCount(summary.reportable_total)} fora de contas internas/teste`}
          />
          <StatCard label="Android" value={summary.by_source.android} description="signup_source=android" />
          <StatCard label="Web" value={summary.by_source.web} description="signup_source=web" />
          <StatCard label="PWA" value={summary.by_source.pwa} description="signup_source=pwa" />
          <StatCard
            label="Desconhecido"
            value={summary.by_source.unknown}
            description={`${summary.unknown_share.value}% da coorte`}
          />
        </div>
        <p className="mt-3 text-[11px] leading-relaxed text-amber-700 dark:text-amber-400">
          {definitions.unknown_note}
        </p>
      </Block>

      <Block
        title={allTime ? "Android — desde sempre" : "Android — mesma janela"}
        note="Instalações e usuários são populações diferentes: cada linha traz o seu próprio denominador e nada é dividido entre elas."
      >
        <FunnelRow
          label="Instalações observadas"
          value={formatCount(funnel.installations_observed)}
          definition={definitions.installations_observed}
        />
        <FunnelRow
          label="Chegaram à autenticação"
          value={formatCount(funnel.reached_authentication.numerator)}
          detail={formatRateWithSample(funnel.reached_authentication)}
          definition={definitions.reached_authentication}
        />
        <FunnelRow
          label="Usuários criados pelo Android"
          value={formatCount(funnel.users_created_from_android)}
          definition={definitions.users_created_from_android}
        />
        <FunnelRow
          label="Instalações vinculadas"
          value={formatCount(funnel.linked_installations.numerator)}
          detail={formatRateWithSample(funnel.linked_installations)}
          definition={definitions.linked_installations}
        />
        <FunnelRow
          label="Continuam anônimas"
          value={formatCount(funnel.anonymous_installations)}
          definition={definitions.anonymous_installations}
        />

        <div className="mt-3 rounded-xl border border-dashed border-[var(--border)] p-3">
          <p className="text-xs font-semibold text-[var(--text)]">Eventos de tentativa de autenticação</p>
          <p className="mt-0.5 text-[10px] leading-relaxed text-[var(--text-dim)]">{definitions.auth_attempt_events}</p>
          <div className="mt-2 flex flex-wrap gap-x-5 gap-y-1">
            {Object.entries(funnel.auth_attempt_events).map(([name, count]) => (
              <span key={name} className="text-xs text-[var(--text-muted)]">
                {ATTEMPT_EVENT_LABELS[name] ?? name}:{" "}
                <strong className="text-[var(--text)]">{formatCount(count)}</strong>
              </span>
            ))}
          </div>
        </div>
      </Block>
    </div>
  );
}

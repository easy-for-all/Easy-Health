"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { useObservability } from "./use-observability";
import { OverviewCards } from "./overview-cards";
import { IncidentsTable } from "./incidents-table";
import { AndroidBuildsTable } from "./android-builds-table";
import { HeartbeatsTable } from "./heartbeats-table";
import { InvestigationTimeline } from "./investigation-timeline";
import { StatusBadge } from "./status-badge";
import { formatDateTime } from "./metric-cell";

// Six cards, three tables, one collapsible investigation panel.
//
// The client-side gate below mirrors admin/page.tsx and is a redirect for
// convenience only — the real authorization is `require_admin!` on every action
// of Api::V1::Admin::ObservabilityController.

export default function ObservabilityPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const [range, setRange] = useState("24h");
  const { data, loading, error, reload } = useObservability(range);

  useEffect(() => {
    if (authLoading) return;
    if (!user?.admin) router.replace("/");
  }, [user, authLoading, router]);

  if (authLoading || (loading && !data)) return <LoadingScreen />;
  if (!user?.admin) return null;

  return (
    <main className="min-h-screen bg-[var(--bg)] px-4 py-8">
      <div className="mx-auto max-w-6xl space-y-8">
        <header className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <Link href="/admin" className="text-xs text-[var(--text-dim)] hover:text-[var(--text)]">
              ← Voltar ao admin
            </Link>
            <h1 className="mt-1 text-2xl font-bold text-[var(--text)]">Observabilidade</h1>
            {data ? (
              <p className="mt-1 flex items-center gap-2 text-sm text-[var(--text-muted)]">
                <StatusBadge status={data.overall_status} />
                <span>atualizado {formatDateTime(data.generated_at)}</span>
              </p>
            ) : null}
          </div>

          <button
            type="button"
            onClick={() => reload({ refresh: true })}
            className="rounded-full border border-[var(--border)] bg-[var(--surface)] px-3 py-1.5 text-xs text-[var(--text-muted)] hover:text-[var(--text)]"
          >
            Atualizar agora
          </button>
        </header>

        {error ? (
          <div className="rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-300">
            {error}
          </div>
        ) : null}

        {data ? (
          <>
            <OverviewCards cards={data.cards} />

            {/* Grey cards need an explanation, or an operator reads them as fine. */}
            {data.data_quality.notes.length > 0 ? (
              <section className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
                <h2 className="text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
                  Qualidade dos dados
                </h2>
                <ul className="mt-2 space-y-1">
                  {data.data_quality.notes.map((note) => (
                    <li key={note} className="text-xs text-[var(--text-muted)]">
                      • {note}
                    </li>
                  ))}
                </ul>
                <p className="mt-2 text-xs text-[var(--text-dim)]">
                  Última verificação: {formatDateTime(data.data_quality.last_run_at)}
                  {data.data_quality.stale ? " (atrasada)" : ""}
                </p>
              </section>
            ) : null}

            <IncidentsTable incidents={data.incidents} onChanged={() => reload({ refresh: true })} />
            <AndroidBuildsTable rows={data.android_builds} range={range} onRangeChange={setRange} />
            <HeartbeatsTable rows={data.heartbeats} />
            <InvestigationTimeline />
          </>
        ) : null}
      </div>
    </main>
  );
}

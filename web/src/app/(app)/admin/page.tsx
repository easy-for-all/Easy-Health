"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";

type AdminStats = {
  total_users: number;
  trial_active_count: number;
  trial_expired_count: number;
  premium_count: number;
  stripe_trialing_count: number;
  users_created_workouts: number;
  users_completed_workouts: number;
  users_with_2plus_sessions: number;
  users_with_3plus_sessions: number;
  active_last_7_days: number;
  active_last_30_days: number;
  retention_d1: number;
  retention_d7: number;
  retention_d30: number;
  conversion_trial_to_subscription: number;
  conversion_signup_to_workout_created: number;
  conversion_plan_to_session: number;
  conversion_session_to_subscription: number;
  total_workout_plans: number;
  total_workout_sessions: number;
  total_uploads: number;
};

type AdminUser = {
  id: number;
  name: string;
  email: string;
  created_at: string;
  trial_status: "trial_active" | "trial_expired" | "premium" | "stripe_trial" | "no_trial";
  trial_days_remaining: number;
  trial_ends_at: string | null;
  workouts_created: number;
  sessions_completed: number;
  last_session_at: string | null;
  is_recurring: boolean;
  engagement_level: "low" | "medium" | "high";
};

type UsersResponse = {
  users: AdminUser[];
  total: number;
  page: number;
  per: number;
};

const FILTERS = [
  { value: "", label: "Todos" },
  { value: "trial_active", label: "Trial ativo" },
  { value: "trial_expired", label: "Trial expirado" },
  { value: "premium", label: "Premium" },
  { value: "no_workout", label: "Sem treino criado" },
  { value: "plan_no_session", label: "Criou treino, não executou" },
  { value: "1_session", label: "Executou 1 treino" },
  { value: "3plus_sessions", label: "Executou 3+ treinos" },
  { value: "active_7d", label: "Ativo últimos 7 dias" },
  { value: "inactive_7d", label: "Inativo últimos 7 dias" },
];

const STATUS_LABELS: Record<AdminUser["trial_status"], { label: string; cls: string }> = {
  trial_active: { label: "Trial ativo", cls: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300" },
  trial_expired: { label: "Trial expirado", cls: "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300" },
  premium: { label: "Premium", cls: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300" },
  stripe_trial: { label: "Trial Stripe", cls: "bg-purple-100 text-purple-700 dark:bg-purple-900 dark:text-purple-300" },
  no_trial: { label: "Sem trial", cls: "bg-gray-100 text-gray-500 dark:bg-gray-800 dark:text-gray-400" },
};

function StatCard({ label, value, description, pct }: { label: string; value: number | undefined; description: string; pct?: boolean }) {
  const display = value === undefined ? "—" : pct ? `${value}%` : value.toLocaleString("pt-BR");
  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <p className="text-3xl font-bold text-primary-600">{display}</p>
      <p className="mt-1 text-sm font-semibold text-[var(--text)]">{label}</p>
      <p className="mt-0.5 text-xs text-[var(--text-dim)]">{description}</p>
    </div>
  );
}

export default function AdminPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const [usersData, setUsersData] = useState<UsersResponse | null>(null);
  const [usersLoading, setUsersLoading] = useState(false);
  const [filter, setFilter] = useState("");
  const [page, setPage] = useState(1);

  useEffect(() => {
    if (authLoading) return;
    if (!user?.admin) {
      router.replace("/");
      return;
    }
    api.get<AdminStats>("/api/v1/admin/stats")
      .then(setStats)
      .catch(() => setError("Erro ao carregar estatísticas."))
      .finally(() => setLoading(false));
  }, [user, authLoading, router]);

  useEffect(() => {
    if (!user?.admin) return;
    setUsersLoading(true);
    const params = new URLSearchParams({ page: String(page) });
    if (filter) params.set("filter", filter);
    api.get<UsersResponse>(`/api/v1/admin/users?${params}`)
      .then(setUsersData)
      .catch(() => {})
      .finally(() => setUsersLoading(false));
  }, [user, filter, page]);

  if (authLoading || loading) return <LoadingScreen />;
  if (!user?.admin) return null;

  const totalPages = usersData ? Math.ceil(usersData.total / usersData.per) : 0;

  return (
    <div className="min-h-screen bg-[var(--bg)] px-4 py-8">
      <div className="mx-auto max-w-3xl space-y-8">

        {/* Header */}
        <div className="flex items-center gap-3">
          <span className="text-2xl">📊</span>
          <div>
            <h1 className="text-xl font-bold text-[var(--text)]">Painel Administrativo</h1>
            <p className="text-sm text-[var(--text-muted)]">Visão geral da plataforma</p>
          </div>
        </div>

        {error && (
          <div className="rounded-xl bg-[var(--hot-soft)] px-4 py-3 text-sm text-[var(--hot)]">{error}</div>
        )}

        {/* Trial & Subscription */}
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">Status de acesso</h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <StatCard label="Cadastrados" value={stats?.total_users} description="Total de contas" />
            <StatCard label="Trial ativo" value={stats?.trial_active_count} description="Dentro dos 7 dias" />
            <StatCard label="Trial expirado" value={stats?.trial_expired_count} description="Sem assinatura" />
            <StatCard label="Premium" value={stats?.premium_count} description="Assinatura ativa" />
          </div>
        </section>

        {/* Engagement */}
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">Engajamento</h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            <StatCard label="Criaram treino" value={stats?.users_created_workouts} description="Usuários com plano gerado" />
            <StatCard label="Executaram treino" value={stats?.users_completed_workouts} description="Pelo menos 1 sessão" />
            <StatCard label="2+ treinos" value={stats?.users_with_2plus_sessions} description="Realizaram 2 ou mais" />
            <StatCard label="3+ treinos" value={stats?.users_with_3plus_sessions} description="Usuários engajados" />
            <StatCard label="Ativos 7d" value={stats?.active_last_7_days} description="Sessão nos últimos 7 dias" />
            <StatCard label="Ativos 30d" value={stats?.active_last_30_days} description="Sessão nos últimos 30 dias" />
          </div>
        </section>

        {/* Retention */}
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">Retenção</h2>
          <div className="grid grid-cols-3 gap-3">
            <StatCard label="D1" value={stats?.retention_d1} description="Voltou no dia seguinte" pct />
            <StatCard label="D7" value={stats?.retention_d7} description="Voltou no dia 7" pct />
            <StatCard label="D30" value={stats?.retention_d30} description="Voltou no dia 30" pct />
          </div>
        </section>

        {/* Conversion funnel */}
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">Funil de conversão</h2>
          <div className="grid grid-cols-2 gap-3">
            <StatCard label="Cadastro → Treino criado" value={stats?.conversion_signup_to_workout_created} description="% que gerou um plano" pct />
            <StatCard label="Treino criado → Executado" value={stats?.conversion_plan_to_session} description="% que treinou" pct />
            <StatCard label="Executou → Assinou" value={stats?.conversion_session_to_subscription} description="% que virou premium" pct />
            <StatCard label="Trial → Assinatura" value={stats?.conversion_trial_to_subscription} description="% total de conversão" pct />
          </div>
        </section>

        {/* Users table */}
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">Usuários</h2>

          {/* Filters */}
          <div className="mb-3 flex flex-wrap gap-2">
            {FILTERS.map((f) => (
              <button
                key={f.value}
                onClick={() => { setFilter(f.value); setPage(1); }}
                className={`rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                  filter === f.value
                    ? "bg-primary-500 text-white"
                    : "bg-[var(--surface)] border border-[var(--border)] text-[var(--text-muted)] hover:text-[var(--text)]"
                }`}
              >
                {f.label}
              </button>
            ))}
          </div>

          {usersLoading ? (
            <div className="py-8 text-center text-sm text-[var(--text-muted)]">Carregando...</div>
          ) : (
            <div className="overflow-x-auto rounded-2xl border border-[var(--border)] bg-[var(--surface)]">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-[var(--border)] text-left text-xs text-[var(--text-muted)]">
                    <th className="px-4 py-3 font-medium">Usuário</th>
                    <th className="px-4 py-3 font-medium">Status</th>
                    <th className="px-4 py-3 font-medium text-center">Dias</th>
                    <th className="px-4 py-3 font-medium text-center">Treinos</th>
                    <th className="px-4 py-3 font-medium text-center">Sessões</th>
                    <th className="px-4 py-3 font-medium text-center">Recorrente</th>
                    <th className="px-4 py-3 font-medium text-center">Engaj.</th>
                    <th className="px-4 py-3 font-medium">Última sessão</th>
                  </tr>
                </thead>
                <tbody>
                  {usersData?.users.map((u) => {
                    const status = STATUS_LABELS[u.trial_status];
                    return (
                      <tr key={u.id} className="border-b border-[var(--border)] last:border-0 hover:bg-[var(--surface-hover)]">
                        <td className="px-4 py-3">
                          <p className="font-medium text-[var(--text)]">{u.name}</p>
                          <p className="text-xs text-[var(--text-muted)]">{u.email}</p>
                          <p className="text-xs text-[var(--text-dim)]">{new Date(u.created_at).toLocaleDateString("pt-BR")}</p>
                        </td>
                        <td className="px-4 py-3">
                          <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${status.cls}`}>
                            {status.label}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-center text-[var(--text-muted)]">
                          {u.trial_status === "trial_active" ? u.trial_days_remaining : "—"}
                        </td>
                        <td className="px-4 py-3 text-center font-medium text-[var(--text)]">{u.workouts_created}</td>
                        <td className="px-4 py-3 text-center font-medium text-[var(--text)]">{u.sessions_completed}</td>
                        <td className="px-4 py-3 text-center">
                          {u.is_recurring
                            ? <span className="text-green-500 font-bold">Sim</span>
                            : <span className="text-[var(--text-dim)]">Não</span>
                          }
                        </td>
                        <td className="px-4 py-3 text-center">
                          <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                            u.engagement_level === "high" ? "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
                            : u.engagement_level === "medium" ? "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300"
                            : "bg-gray-100 text-gray-500 dark:bg-gray-800 dark:text-gray-400"
                          }`}>
                            {u.engagement_level === "high" ? "Alto" : u.engagement_level === "medium" ? "Médio" : "Baixo"}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-xs text-[var(--text-muted)]">
                          {u.last_session_at ? new Date(u.last_session_at).toLocaleDateString("pt-BR") : "—"}
                        </td>
                      </tr>
                    );
                  })}
                  {usersData?.users.length === 0 && (
                    <tr>
                      <td colSpan={8} className="px-4 py-8 text-center text-[var(--text-muted)]">
                        Nenhum usuário encontrado
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          )}

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="mt-3 flex items-center justify-between text-sm text-[var(--text-muted)]">
              <span>{usersData?.total} usuários</span>
              <div className="flex gap-2">
                <button
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={page === 1}
                  className="rounded-lg border border-[var(--border)] px-3 py-1 disabled:opacity-40 hover:text-[var(--text)] transition-colors"
                >
                  ←
                </button>
                <span className="px-2 py-1">{page} / {totalPages}</span>
                <button
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                  disabled={page === totalPages}
                  className="rounded-lg border border-[var(--border)] px-3 py-1 disabled:opacity-40 hover:text-[var(--text)] transition-colors"
                >
                  →
                </button>
              </div>
            </div>
          )}
        </section>

        {/* Totals (legacy) */}
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">Totais</h2>
          <div className="grid grid-cols-3 gap-3">
            <StatCard label="Planos criados" value={stats?.total_workout_plans} description="Total no sistema" />
            <StatCard label="Sessões" value={stats?.total_workout_sessions} description="Total de treinos" />
            <StatCard label="Uploads" value={stats?.total_uploads} description="Fotos e exames" />
          </div>
        </section>

      </div>
    </div>
  );
}

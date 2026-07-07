"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { OnboardingAnalyticsSection } from "./onboarding-analytics";
import type { OnboardingAnalytics } from "./onboarding-analytics/types";

type AdminStats = {
  total_users: number;
  trial_active_count: number;
  trial_expired_count: number;
  trial_expiring_24h_count?: number;
  trial_expiring_48h_count?: number;
  trial_expired_without_subscription_count?: number;
  premium_count: number;
  stripe_trialing_count: number;
  users_created_workouts: number;
  users_completed_workouts: number;
  users_plan_not_started?: number;
  users_with_2plus_sessions: number;
  users_with_3plus_sessions: number;
  active_last_7_days: number;
  active_last_30_days: number;
  inactive_3_days_count?: number;
  inactive_7_days_count?: number;
  inactive_15_days_count?: number;
  churn_risk_count?: number;
  completed_partial_recently_count?: number;
  make_events_delivered_today?: number;
  make_events_failed?: number;
  recent_relationship_events?: Array<{ id: number; user_id: number; event_name: string; occurred_at: string | null; make_delivery_status: string }>;
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
  onboarding_analytics?: OnboardingAnalytics;
};

type AdminUser = {
  id: number;
  admin_display_id: string;
  display_name: string;
  created_at: string;
  trial_status: "trial_active" | "trial_expired" | "premium" | "stripe_trial" | "no_trial";
  trial_days_remaining: number;
  workouts_created: number;
  sessions_completed: number;
  last_activity_at: string | null;
  last_activity_label: string;
  engagement_level: "low" | "medium" | "high";
  active_segments?: string[];
};

type AdminUserDetail = AdminUser & {
  name: string;
  email: string;
  trial_ends_at: string | null;
  recent_events: Array<{ name: string; created_at: string; make_delivery_status?: string }>;
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
  { value: "segment:inactive_3_days", label: "Inativo 3d" },
  { value: "segment:inactive_15_days", label: "Inativo 15d" },
  { value: "segment:churn_risk", label: "Churn risk" },
  { value: "segment:completed_partial_recently", label: "Parcial recente" },
  { value: "engagement_high", label: "Engaj. Alto" },
  { value: "engagement_medium", label: "Engaj. Médio" },
  { value: "engagement_low", label: "Engaj. Baixo" },
];

const STATUS_LABELS: Record<AdminUser["trial_status"], { label: string; cls: string }> = {
  trial_active: { label: "Trial ativo", cls: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300" },
  trial_expired: { label: "Trial expirado", cls: "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300" },
  premium: { label: "Premium", cls: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300" },
  stripe_trial: { label: "Trial Stripe", cls: "bg-purple-100 text-purple-700 dark:bg-purple-900 dark:text-purple-300" },
  no_trial: { label: "Sem trial", cls: "bg-gray-100 text-gray-500 dark:bg-gray-800 dark:text-gray-400" },
};

const ENGAGEMENT_LABELS: Record<AdminUser["engagement_level"], { label: string; cls: string }> = {
  high: { label: "Alto", cls: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300" },
  medium: { label: "Médio", cls: "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300" },
  low: { label: "Baixo", cls: "bg-gray-100 text-gray-500 dark:bg-gray-800 dark:text-gray-400" },
};

const EVENT_LABELS: Record<string, string> = {
  signup_completed: "Cadastro",
  trial_started: "Trial iniciado",
  onboarding_completed: "Onboarding concluído",
  workout_created: "Treino criado",
  workout_started: "Treino iniciado",
  workout_completed: "Treino concluído",
  progress_viewed: "Progresso visualizado",
  favorite_added: "Favorito adicionado",
  photo_uploaded: "Foto enviada",
  exam_uploaded: "Exame enviado",
  bioimpedance_added: "Bioimpedância adicionada",
  paywall_viewed: "Paywall visto",
  checkout_started: "Checkout iniciado",
  subscription_created: "Assinatura criada",
  subscription_renewed: "Assinatura renovada",
  subscription_canceled: "Assinatura cancelada",
  trial_expired: "Trial expirado",
  trial_day_1: "Trial D1",
  trial_day_3: "Trial D3",
  trial_day_6: "Trial D6",
  first_workout_created: "Primeiro treino criado",
  first_workout_completed: "Primeiro treino concluído",
  workout_completed_partial: "Treino parcial",
  workout_abandoned: "Treino abandonado",
  user_inactive_3_days: "Inativo 3 dias",
  user_inactive_7_days: "Inativo 7 dias",
  user_inactive_15_days: "Inativo 15 dias",
  body_photo_uploaded: "Foto corporal enviada",
  body_photo_deleted: "Foto corporal excluída",
  plan_created_but_not_used: "Plano sem uso",
  trial_expired_without_subscription: "Trial expirado sem assinatura",
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

function DetailRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-4 border-b border-[var(--border)] pb-2 last:border-0">
      <span className="shrink-0 text-xs text-[var(--text-muted)]">{label}</span>
      <span className="text-right text-xs font-medium text-[var(--text)]">{value}</span>
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

  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [userDetail, setUserDetail] = useState<AdminUserDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

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

  function openUserDetail(id: number) {
    setSelectedUserId(id);
    setUserDetail(null);
    setDetailLoading(true);
    api.get<AdminUserDetail>(`/api/v1/admin/users/${id}`)
      .then(setUserDetail)
      .finally(() => setDetailLoading(false));
  }

  function closeDetail() {
    setSelectedUserId(null);
    setUserDetail(null);
  }

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
            <StatCard label="Treino sem execução" value={stats?.users_plan_not_started} description="Plano criado sem sessão" />
            <StatCard label="Executaram treino" value={stats?.users_completed_workouts} description="Pelo menos 1 sessão" />
            <StatCard label="2+ treinos" value={stats?.users_with_2plus_sessions} description="Realizaram 2 ou mais" />
            <StatCard label="3+ treinos" value={stats?.users_with_3plus_sessions} description="Usuários engajados" />
            <StatCard label="Ativos 7d" value={stats?.active_last_7_days} description="Sessão nos últimos 7 dias" />
            <StatCard label="Ativos 30d" value={stats?.active_last_30_days} description="Sessão nos últimos 30 dias" />
          </div>
        </section>

        {/* Relationship journey */}
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">Jornada</h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <StatCard label="Expira 24h" value={stats?.trial_expiring_24h_count} description="Trial ativo" />
            <StatCard label="Expira 48h" value={stats?.trial_expiring_48h_count} description="Trial ativo" />
            <StatCard label="Inativos 7d" value={stats?.inactive_7_days_count} description="Segmento ativo" />
            <StatCard label="Churn risk" value={stats?.churn_risk_count} description="Assinantes em risco" />
            <StatCard label="Parcial recente" value={stats?.completed_partial_recently_count} description="Últimos 7 dias" />
            <StatCard label="Make hoje" value={stats?.make_events_delivered_today} description="Eventos entregues" />
            <StatCard label="Make falhou" value={stats?.make_events_failed} description="Eventos com erro" />
            <StatCard label="Trial sem assinatura" value={stats?.trial_expired_without_subscription_count} description="Expirados" />
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

        <OnboardingAnalyticsSection />

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
                    <th className="px-4 py-3 font-medium text-center">Engaj.</th>
                    <th className="px-4 py-3 font-medium">Última atividade</th>
                    <th className="px-4 py-3 font-medium text-center">Ações</th>
                  </tr>
                </thead>
                <tbody>
                  {usersData?.users.map((u) => {
                    const status = STATUS_LABELS[u.trial_status];
                    const engaj = ENGAGEMENT_LABELS[u.engagement_level];
                    return (
                      <tr key={u.id} className="border-b border-[var(--border)] last:border-0 hover:bg-[var(--surface-hover)]">
                        <td className="px-4 py-3">
                          <p className="font-medium text-[var(--text)]">{u.display_name}</p>
                          <p className="text-xs text-[var(--text-dim)]">{u.admin_display_id}</p>
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
                          <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${engaj.cls}`}>
                            {engaj.label}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-xs text-[var(--text-muted)]">
                          <div>{u.last_activity_label}</div>
                          {u.active_segments && u.active_segments.length > 0 && (
                            <div className="mt-1 max-w-[180px] truncate text-[10px] text-[var(--text-dim)]">
                              {u.active_segments.slice(0, 3).join(", ")}
                            </div>
                          )}
                        </td>
                        <td className="px-4 py-3 text-center">
                          <button
                            onClick={() => openUserDetail(u.id)}
                            className="rounded-lg border border-[var(--border)] px-3 py-1 text-xs text-[var(--text-muted)] transition-colors hover:border-primary-500 hover:text-primary-600"
                          >
                            Ver
                          </button>
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

      {/* User Detail Modal */}
      {selectedUserId !== null && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={(e) => { if (e.target === e.currentTarget) closeDetail(); }}
        >
          <div className="relative w-full max-w-md rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-6 shadow-xl">
            <button
              onClick={closeDetail}
              className="absolute right-4 top-4 flex h-7 w-7 items-center justify-center rounded-full text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)] transition-colors"
            >
              ✕
            </button>

            <p className="mb-4 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-700 dark:bg-amber-900/30 dark:text-amber-300">
              Dados pessoais — uso interno
            </p>

            {detailLoading ? (
              <div className="py-8 text-center text-sm text-[var(--text-muted)]">Carregando...</div>
            ) : userDetail ? (
              <div className="space-y-3">
                <div className="mb-4">
                  <p className="text-base font-semibold text-[var(--text)]">{userDetail.display_name}</p>
                  <p className="text-xs text-[var(--text-dim)]">{userDetail.admin_display_id}</p>
                </div>

                <DetailRow label="Nome completo" value={userDetail.name || "—"} />
                <DetailRow label="E-mail" value={userDetail.email} />
                <DetailRow label="Cadastro" value={new Date(userDetail.created_at).toLocaleDateString("pt-BR")} />
                <DetailRow
                  label="Status"
                  value={
                    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_LABELS[userDetail.trial_status].cls}`}>
                      {STATUS_LABELS[userDetail.trial_status].label}
                    </span>
                  }
                />
                {userDetail.trial_status === "trial_active" && (
                  <DetailRow label="Dias restantes" value={`${userDetail.trial_days_remaining} dias`} />
                )}
                {userDetail.trial_ends_at && (
                  <DetailRow label="Trial expira" value={new Date(userDetail.trial_ends_at).toLocaleDateString("pt-BR")} />
                )}
                <DetailRow label="Treinos criados" value={userDetail.workouts_created} />
                <DetailRow label="Sessões concluídas" value={userDetail.sessions_completed} />
                <DetailRow label="Última atividade" value={userDetail.last_activity_label} />
                <DetailRow
                  label="Engajamento"
                  value={
                    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${ENGAGEMENT_LABELS[userDetail.engagement_level].cls}`}>
                      {ENGAGEMENT_LABELS[userDetail.engagement_level].label}
                    </span>
                  }
                />

                {userDetail.recent_events.length > 0 && (
                  <div className="mt-4">
                    <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
                      Eventos recentes
                    </p>
                    <div className="space-y-1.5 rounded-xl border border-[var(--border)] p-3">
                      {userDetail.recent_events.map((ev, i) => (
                        <div key={i} className="flex items-center justify-between text-xs">
                          <span className="text-[var(--text)]">{EVENT_LABELS[ev.name] ?? ev.name}</span>
                          <span className="text-right text-[var(--text-dim)]">
                            {new Date(ev.created_at).toLocaleDateString("pt-BR")}
                            {ev.make_delivery_status && ` · ${ev.make_delivery_status}`}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            ) : (
              <div className="py-8 text-center text-sm text-[var(--text-muted)]">Erro ao carregar dados.</div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

"use client";

import Link from "next/link";
import Image from "next/image";
import { useTranslations } from "next-intl";
import { useAuth } from "@/features/auth/auth-context";
import { usePersonalDashboard } from "@/features/personal/use-personal";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { ClientSummary } from "@/shared/types/personal";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

function StatCard({ label, value, alert }: { label: string; value: number; alert?: boolean }) {
  return (
    <div className={`flex flex-col items-center justify-center rounded-2xl p-4 ${alert && value > 0 ? "bg-amber-50 dark:bg-amber-900/20" : "bg-white dark:bg-gray-900"}`}>
      <span className={`text-2xl font-bold ${alert && value > 0 ? "text-amber-600 dark:text-amber-400" : "text-gray-900 dark:text-gray-100"}`}>{value}</span>
      <span className="mt-1 text-center text-xs text-gray-500 dark:text-gray-400">{label}</span>
    </div>
  );
}

function ClientRow({ client }: { client: ClientSummary }) {
  const t = useTranslations("personal");
  const avatarSrc = client.avatar_url
    ? client.avatar_url.startsWith("http") ? client.avatar_url : `${API_URL}${client.avatar_url}`
    : null;

  const lastTrainedLabel = () => {
    const days = client.days_without_training;
    if (days == null) return t("never");
    if (days === 0) return t("today");
    return t("days_ago", { days });
  };

  return (
    <Link href={`/personal/clients/${client.client_id}`} className="flex items-center gap-3 rounded-xl bg-white p-4 shadow-sm dark:bg-gray-900 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors">
      {avatarSrc ? (
        <Image src={avatarSrc} alt={client.name} width={40} height={40} className="rounded-full object-cover flex-shrink-0" />
      ) : (
        <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-primary-100 text-primary-700 dark:bg-primary-900 dark:text-primary-300 font-semibold">
          {client.name.charAt(0).toUpperCase()}
        </div>
      )}

      <div className="flex-1 min-w-0">
        <p className="font-medium text-gray-900 dark:text-gray-100 truncate">{client.name}</p>
        <p className="text-xs text-gray-500 dark:text-gray-400">{lastTrainedLabel()}</p>
      </div>

      <div className="flex items-center gap-2 flex-shrink-0">
        {client.weekly_adherence != null && (
          <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${
            client.weekly_adherence >= 80
              ? "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
              : client.weekly_adherence >= 50
              ? "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400"
              : "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
          }`}>
            {client.weekly_adherence}%
          </span>
        )}
        {client.inactive_alert && (
          <span className="flex h-2 w-2 rounded-full bg-amber-500" />
        )}
      </div>
    </Link>
  );
}

export default function PersonalDashboardPage() {
  const t = useTranslations("personal");
  const { user } = useAuth();
  const { dashboard, clients, loading } = usePersonalDashboard();

  if (!user || user.account_type !== "personal_trainer") {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Link href="/personal" className="rounded-xl bg-primary-500 px-5 py-3 text-sm font-semibold text-white">
          Ativar conta Personal Trainer
        </Link>
      </div>
    );
  }

  if (loading || !dashboard) return <LoadingScreen />;

  return (
    <div className="min-h-screen bg-gray-50 pb-24 dark:bg-gray-950">
      <header className="bg-gradient-to-b from-primary-600 to-primary-500 px-4 pt-12 pb-6 text-white">
        <p className="text-sm opacity-80">Olá, {user.name}</p>
        <h1 className="text-xl font-bold">{t("dashboard_title")}</h1>
      </header>

      <div className="mx-auto max-w-lg px-4 py-5 space-y-5">
        {/* Stats grid */}
        <div className="grid grid-cols-2 gap-3">
          <StatCard label={t("active_clients")} value={dashboard.active_clients} />
          <StatCard label={t("inactive_7d")} value={dashboard.inactive_7_days} alert />
          <StatCard label={t("high_adherence")} value={dashboard.high_adherence} />
          <StatCard label={t("needs_plan")} value={dashboard.needs_new_plan} alert />
        </div>

        {/* Quick actions */}
        <div className="flex gap-3">
          <Link
            href="/personal/clients/invite"
            className="flex-1 rounded-xl bg-primary-500 py-3 text-center text-sm font-semibold text-white"
          >
            + Convidar aluno
          </Link>
          <Link
            href="/personal/clients"
            className="flex-1 rounded-xl bg-white py-3 text-center text-sm font-semibold text-gray-700 shadow-sm dark:bg-gray-900 dark:text-gray-300"
          >
            Ver todos →
          </Link>
        </div>

        {/* Client list */}
        {clients.length === 0 ? (
          <div className="py-8 text-center">
            <p className="text-sm text-gray-500 dark:text-gray-400">{t("no_clients")}</p>
          </div>
        ) : (
          <div className="space-y-2">
            <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">Alunos</h2>
            {clients.map((c) => <ClientRow key={c.client_id} client={c} />)}
          </div>
        )}
      </div>
    </div>
  );
}

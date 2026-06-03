"use client";

import Link from "next/link";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { usePersonalClients } from "@/features/personal/use-personal";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { ClientSummary } from "@/shared/types/personal";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

function AdherenceBadge({ pct }: { pct: number | null | undefined }) {
  if (pct == null) return null;
  const color = pct >= 80 ? "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
    : pct >= 50 ? "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400"
    : "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400";
  return <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${color}`}>{pct}%</span>;
}

function ClientCard({ client }: { client: ClientSummary }) {
  const t = useTranslations("personal");
  const avatarSrc = client.avatar_url
    ? client.avatar_url.startsWith("http") ? client.avatar_url : `${API_URL}${client.avatar_url}`
    : null;

  const lastTrained = () => {
    const d = client.days_without_training;
    if (d == null) return t("never");
    if (d === 0) return t("today");
    return t("days_ago", { days: d });
  };

  return (
    <Link href={`/personal/clients/${client.client_id}`}
      className="flex items-center gap-3 rounded-2xl bg-white p-4 shadow-sm dark:bg-gray-900 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors">
      {avatarSrc ? (
        <Image src={avatarSrc} alt={client.name} width={44} height={44} className="rounded-full object-cover flex-shrink-0" />
      ) : (
        <div className="flex h-11 w-11 flex-shrink-0 items-center justify-center rounded-full bg-primary-100 text-primary-700 dark:bg-primary-900 dark:text-primary-300 font-semibold text-lg">
          {client.name.charAt(0).toUpperCase()}
        </div>
      )}

      <div className="flex-1 min-w-0">
        <p className="font-semibold text-gray-900 dark:text-gray-100 truncate">{client.name}</p>
        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{t("last_session")}: {lastTrained()}</p>
        <div className="mt-1.5 flex items-center gap-2">
          {client.inactive_alert && (
            <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700 dark:bg-amber-900/30 dark:text-amber-400">
              {t("alert_inactive")}
            </span>
          )}
          {client.needs_new_plan && (
            <span className="rounded-full bg-blue-100 px-2 py-0.5 text-xs font-medium text-blue-700 dark:bg-blue-900/30 dark:text-blue-400">
              {t("alert_needs_plan")}
            </span>
          )}
        </div>
      </div>

      <div className="flex-shrink-0">
        <AdherenceBadge pct={client.weekly_adherence} />
      </div>
    </Link>
  );
}

export default function PersonalClientsPage() {
  const t = useTranslations("personal");
  const router = useRouter();
  const { clients, loading } = usePersonalClients();

  if (loading) return <LoadingScreen />;

  return (
    <div className="min-h-screen bg-gray-50 pb-24 dark:bg-gray-950">
      <header className="sticky top-0 z-10 flex items-center gap-3 border-b border-gray-100 bg-white/90 px-4 py-4 backdrop-blur-sm dark:border-gray-800 dark:bg-gray-950/90">
        <button onClick={() => router.back()} className="text-gray-500 dark:text-gray-400">←</button>
        <h1 className="flex-1 text-base font-semibold text-gray-900 dark:text-gray-100">{t("clients_title")}</h1>
        <Link href="/personal/clients/invite" className="text-sm font-medium text-primary-500">+ Convidar</Link>
      </header>

      <div className="mx-auto max-w-lg space-y-3 px-4 py-4">
        {clients.length === 0 ? (
          <div className="py-12 text-center space-y-3">
            <p className="text-sm text-gray-500 dark:text-gray-400">{t("no_clients")}</p>
            <Link href="/personal/clients/invite" className="inline-block rounded-xl bg-primary-500 px-5 py-2.5 text-sm font-semibold text-white">
              {t("invite_now")}
            </Link>
          </div>
        ) : (
          clients.map((c) => <ClientCard key={c.client_id} client={c} />)
        )}
      </div>
    </div>
  );
}

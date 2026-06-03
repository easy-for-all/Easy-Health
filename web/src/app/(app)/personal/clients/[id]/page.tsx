"use client";

import { useState } from "react";
import { useRouter, useParams } from "next/navigation";
import Image from "next/image";
import { useTranslations } from "next-intl";
import { api } from "@/shared/lib/api";
import { usePersonalClient } from "@/features/personal/use-personal";
import { LoadingScreen } from "@/shared/components/loading-screen";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

export default function PersonalClientDetailPage() {
  const params = useParams();
  const router = useRouter();
  const t = useTranslations("personal");
  const { client, loading, notFound } = usePersonalClient(params.id as string);

  if (loading) return <LoadingScreen />;

  if (notFound || !client) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 px-4">
        <p className="text-gray-500 dark:text-gray-400">Aluno não encontrado.</p>
        <button onClick={() => router.back()} className="text-primary-500 text-sm">← Voltar</button>
      </div>
    );
  }

  const avatarSrc = client.avatar_url
    ? client.avatar_url.startsWith("http") ? client.avatar_url : `${API_URL}${client.avatar_url}`
    : null;

  const adherence = client.adherence;

  return (
    <div className="min-h-screen bg-gray-50 pb-24 dark:bg-gray-950">
      <header className="sticky top-0 z-10 flex items-center gap-3 border-b border-gray-100 bg-white/90 px-4 py-4 backdrop-blur-sm dark:border-gray-800 dark:bg-gray-950/90">
        <button onClick={() => router.back()} className="text-gray-500 dark:text-gray-400">←</button>
        <h1 className="text-base font-semibold text-gray-900 dark:text-gray-100">{client.name}</h1>
      </header>

      <div className="mx-auto max-w-lg px-4 py-6 space-y-4">
        {/* Avatar + info */}
        <div className="flex items-center gap-4 rounded-2xl bg-white p-5 shadow-sm dark:bg-gray-900">
          {avatarSrc ? (
            <Image src={avatarSrc} alt={client.name} width={56} height={56} className="rounded-full object-cover" />
          ) : (
            <div className="flex h-14 w-14 items-center justify-center rounded-full bg-primary-100 text-primary-700 dark:bg-primary-900 dark:text-primary-300 text-2xl font-bold">
              {client.name.charAt(0).toUpperCase()}
            </div>
          )}
          <div>
            <p className="font-bold text-gray-900 dark:text-gray-100">{client.name}</p>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              Aluno desde {client.started_at ? new Date(client.started_at).toLocaleDateString() : "—"}
            </p>
          </div>
        </div>

        {/* Aderência */}
        {adherence && (
          <div className="rounded-2xl bg-white p-5 shadow-sm dark:bg-gray-900">
            <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">{t("adherence")}</h2>
            <div className="grid grid-cols-2 gap-3">
              <div className="rounded-xl bg-gray-50 p-3 text-center dark:bg-gray-800">
                <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                  {adherence.weekly_adherence != null ? `${adherence.weekly_adherence}%` : "—"}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400">Esta semana</p>
              </div>
              <div className="rounded-xl bg-gray-50 p-3 text-center dark:bg-gray-800">
                <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                  {adherence.days_without_training != null ? adherence.days_without_training : "—"}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400">Dias sem treinar</p>
              </div>
            </div>
            {adherence.inactive_alert && (
              <div className="mt-3 rounded-xl bg-amber-50 p-3 dark:bg-amber-900/20">
                <p className="text-xs font-medium text-amber-700 dark:text-amber-400">⚠️ Aluno inativo há 7+ dias</p>
              </div>
            )}
          </div>
        )}

        {/* Sessões recentes */}
        {client.recent_sessions && client.recent_sessions.length > 0 && (
          <div className="rounded-2xl bg-white p-5 shadow-sm dark:bg-gray-900">
            <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">Treinos recentes</h2>
            <div className="space-y-2">
              {client.recent_sessions.map((s) => (
                <div key={s.id} className="flex items-center justify-between text-sm">
                  <span className="text-gray-700 dark:text-gray-300">{new Date(s.completed_at).toLocaleDateString()}</span>
                  {s.duration && <span className="text-gray-500 dark:text-gray-400">{s.duration} min</span>}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Ações */}
        <div className="space-y-2">
          {!client.has_active_plan && (
            <AssignPlanButton clientId={client.client_id} />
          )}
        </div>
      </div>
    </div>
  );
}

function AssignPlanButton({ clientId }: { clientId: number }) {
  const t = useTranslations("personal");
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);

  async function assign() {
    setLoading(true);
    try {
      await api.post(`/api/v1/personal/clients/${clientId}/assign_plan`, {});
      setDone(true);
    } finally {
      setLoading(false);
    }
  }

  return (
    <button
      onClick={assign}
      disabled={loading || done}
      className="w-full rounded-2xl bg-primary-500 py-3.5 text-sm font-semibold text-white disabled:opacity-50"
    >
      {done ? "Plano criado ✓" : loading ? "Criando..." : t("assign_plan")}
    </button>
  );
}

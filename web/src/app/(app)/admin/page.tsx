"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";

type AdminStats = {
  total_users: number;
  users_with_active_plan: number;
  users_in_trial: number;
  users_created_workouts: number;
  users_completed_workouts: number;
  total_workout_plans: number;
  total_workout_sessions: number;
  total_uploads: number;
};

type StatCard = {
  label: string;
  value: number | undefined;
  description: string;
};

export default function AdminPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

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

  if (authLoading || loading) return <LoadingScreen />;
  if (!user?.admin) return null;

  const cards: StatCard[] = [
    { label: "Usuários cadastrados", value: stats?.total_users, description: "Total de contas criadas" },
    { label: "Planos ativos", value: stats?.users_with_active_plan, description: "Usuários com assinatura ativa ou em trial" },
    { label: "Em trial", value: stats?.users_in_trial, description: "Usuários no período de avaliação" },
    { label: "Criaram treinos", value: stats?.users_created_workouts, description: "Usuários com plano de treino cadastrado" },
    { label: "Realizaram treinos", value: stats?.users_completed_workouts, description: "Usuários com ao menos 1 sessão registrada" },
    { label: "Total de treinos criados", value: stats?.total_workout_plans, description: "Planos de treino no sistema" },
    { label: "Sessões realizadas", value: stats?.total_workout_sessions, description: "Total de treinos concluídos" },
    { label: "Uploads (fotos/exames)", value: stats?.total_uploads, description: "Total de arquivos enviados" },
  ];

  return (
    <div className="min-h-screen bg-gray-50 px-4 py-8">
      <div className="mx-auto max-w-2xl">
        <div className="mb-8 flex items-center gap-3">
          <span className="text-2xl">📊</span>
          <div>
            <h1 className="text-xl font-bold text-gray-900">Painel Administrativo</h1>
            <p className="text-sm text-gray-500">Visão geral da plataforma</p>
          </div>
        </div>

        {error && (
          <div className="mb-6 rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>
        )}

        <div className="grid grid-cols-2 gap-3">
          {cards.map((card) => (
            <div key={card.label} className="rounded-2xl border border-gray-100 bg-white p-4">
              <p className="text-3xl font-bold text-primary-600">
                {card.value?.toLocaleString("pt-BR") ?? "—"}
              </p>
              <p className="mt-1 text-sm font-semibold text-gray-800">{card.label}</p>
              <p className="mt-0.5 text-xs text-gray-400">{card.description}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

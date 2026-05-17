"use client";

import { useEffect, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { api, ApiError } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { BillingStatus } from "@/shared/types/subscription";

function formatDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "long",
    year: "numeric",
  });
}

function StatusBadge({ status }: { status: string | null }) {
  const labels: Record<string, string> = {
    trialing: "Trial ativo",
    active: "Ativo",
    past_due: "Pagamento pendente",
    canceled: "Cancelado",
    unpaid: "Não pago",
    incomplete: "Incompleto",
  };
  const colors: Record<string, string> = {
    trialing: "bg-blue-100 text-blue-700",
    active: "bg-green-100 text-green-700",
    past_due: "bg-yellow-100 text-yellow-700",
    canceled: "bg-gray-100 text-gray-500",
    unpaid: "bg-red-100 text-red-700",
    incomplete: "bg-gray-100 text-gray-500",
  };

  if (!status) return null;

  return (
    <span className={`inline-block rounded-full px-3 py-1 text-xs font-medium ${colors[status] ?? "bg-gray-100 text-gray-500"}`}>
      {labels[status] ?? status}
    </span>
  );
}

export default function BillingPage() {
  const router = useRouter();
  const [billing, setBilling] = useState<BillingStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<BillingStatus>("/api/v1/billing/status")
      .then(setBilling)
      .catch(() => setError("Não foi possível carregar o status da assinatura."))
      .finally(() => setLoading(false));
  }, []);

  const handleCheckout = useCallback(async (plan: "pro_monthly" | "pro_yearly") => {
    setActionLoading(plan);
    setError(null);
    try {
      const { checkout_url } = await api.post<{ checkout_url: string }>(
        "/api/v1/billing/checkout",
        { plan }
      );
      window.location.href = checkout_url;
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Erro ao iniciar checkout.");
      setActionLoading(null);
    }
  }, []);

  const handlePortal = useCallback(async () => {
    setActionLoading("portal");
    setError(null);
    try {
      const { portal_url } = await api.post<{ portal_url: string }>(
        "/api/v1/billing/portal",
        {}
      );
      window.location.href = portal_url;
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Erro ao abrir portal.");
      setActionLoading(null);
    }
  }, []);

  if (loading) return <LoadingScreen />;

  const hasPlan = billing?.plan != null;
  const isPaid  = billing?.paid === true;
  const isTrialing = billing?.status === "trialing";

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-lg mx-auto px-4 py-8">
        <h1 className="text-2xl font-bold text-gray-900 mb-1">Planos</h1>
        <p className="text-gray-500 text-sm mb-6">Gerencie sua assinatura EasyHealth.</p>

        {hasPlan && (
          <div className="bg-white rounded-2xl border border-gray-200 p-4 mb-6">
            <div className="flex items-center justify-between mb-2">
              <span className="font-medium text-gray-800">
                {billing?.plan === "pro_yearly" ? "Pro Anual" : "Pro Mensal"}
              </span>
              <StatusBadge status={billing?.status ?? null} />
            </div>

            {isTrialing && billing?.trial_end && (
              <p className="text-sm text-blue-600">
                Trial até {formatDate(billing.trial_end)}
              </p>
            )}

            {billing?.current_period_end && !isTrialing && (
              <p className="text-sm text-gray-500">
                Renova em {formatDate(billing.current_period_end)}
              </p>
            )}

            {billing?.cancel_at_period_end && (
              <p className="text-sm text-yellow-600 mt-1">
                Cancela ao fim do período.
              </p>
            )}
          </div>
        )}

        {error && (
          <div className="bg-red-50 text-red-700 rounded-xl px-4 py-3 text-sm mb-4">
            {error}
          </div>
        )}

        <div className="flex flex-col gap-4 mb-6">
          <div className="bg-white rounded-2xl border border-gray-200 p-5">
            <div className="flex items-start justify-between mb-3">
              <div>
                <h2 className="font-semibold text-gray-900">Pro Mensal</h2>
                <p className="text-2xl font-bold text-gray-900 mt-1">
                  R$ 19,90<span className="text-sm font-normal text-gray-500">/mês</span>
                </p>
              </div>
            </div>
            <ul className="text-sm text-gray-600 space-y-1 mb-4">
              <li>✓ Acesso completo a todos os recursos</li>
              <li>✓ Treinos personalizados por IA</li>
              <li>✓ Histórico ilimitado</li>
              <li>✓ 7 dias grátis</li>
            </ul>
            {!isPaid && (
              <button
                onClick={() => handleCheckout("pro_monthly")}
                disabled={actionLoading !== null}
                className="w-full bg-gray-900 text-white rounded-xl py-3 text-sm font-medium disabled:opacity-50"
              >
                {actionLoading === "pro_monthly" ? "Aguarde..." : "Assinar Pro Mensal"}
              </button>
            )}
            {isPaid && billing?.plan === "pro_monthly" && (
              <p className="text-center text-sm text-green-600 font-medium">Plano atual</p>
            )}
          </div>

          <div className="bg-white rounded-2xl border-2 border-gray-900 p-5 relative">
            <span className="absolute -top-3 left-1/2 -translate-x-1/2 bg-gray-900 text-white text-xs font-bold px-3 py-1 rounded-full">
              Mais vantajoso
            </span>
            <div className="flex items-start justify-between mb-3">
              <div>
                <h2 className="font-semibold text-gray-900">Pro Anual</h2>
                <p className="text-2xl font-bold text-gray-900 mt-1">
                  R$ 118,80<span className="text-sm font-normal text-gray-500">/ano</span>
                </p>
                <p className="text-xs text-gray-500">≈ R$ 9,90/mês — economia de ~50%</p>
              </div>
            </div>
            <ul className="text-sm text-gray-600 space-y-1 mb-4">
              <li>✓ Tudo do Pro Mensal</li>
              <li>✓ Metade do preço</li>
              <li>✓ 7 dias grátis</li>
            </ul>
            {!isPaid && (
              <button
                onClick={() => handleCheckout("pro_yearly")}
                disabled={actionLoading !== null}
                className="w-full bg-gray-900 text-white rounded-xl py-3 text-sm font-medium disabled:opacity-50"
              >
                {actionLoading === "pro_yearly" ? "Aguarde..." : "Assinar Pro Anual"}
              </button>
            )}
            {isPaid && billing?.plan === "pro_yearly" && (
              <p className="text-center text-sm text-green-600 font-medium">Plano atual</p>
            )}
          </div>
        </div>

        {billing?.stripe_customer_id && (
          <button
            onClick={handlePortal}
            disabled={actionLoading !== null}
            className="w-full border border-gray-300 text-gray-700 rounded-xl py-3 text-sm font-medium disabled:opacity-50"
          >
            {actionLoading === "portal" ? "Aguarde..." : "Gerenciar assinatura"}
          </button>
        )}
      </div>
    </div>
  );
}

"use client";

import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
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

function daysUntil(iso: string | null): number {
  if (!iso) return 0;
  const diff = new Date(iso).getTime() - Date.now();
  return Math.max(0, Math.ceil(diff / (1000 * 60 * 60 * 24)));
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

  if (!status || status === "none") return null;

  return (
    <span className={`inline-block rounded-full px-3 py-1 text-xs font-medium ${colors[status] ?? "bg-gray-100 text-gray-500"}`}>
      {labels[status] ?? status}
    </span>
  );
}

function StatusMessage({ billing }: { billing: BillingStatus }) {
  if (!billing.plan || billing.plan === "none") {
    return (
      <p className="text-sm text-gray-500">
        Você ainda não possui uma assinatura ativa.{" "}
        <Link href="/pricing" className="text-primary-600 hover:underline font-medium">
          Ver planos
        </Link>
      </p>
    );
  }

  if (billing.status === "trialing") {
    const days = daysUntil(billing.trial_end);
    return (
      <p className="text-sm text-blue-600">
        Você está no teste grátis. Termina em{" "}
        <strong>{days} {days === 1 ? "dia" : "dias"}</strong>{" "}
        ({formatDate(billing.trial_end)}).
      </p>
    );
  }

  if (billing.cancel_at_period_end) {
    return (
      <p className="text-sm text-yellow-700">
        Sua assinatura será cancelada ao final do período ({formatDate(billing.current_period_end)}).
      </p>
    );
  }

  if (billing.status === "active" && billing.current_period_end) {
    return (
      <p className="text-sm text-gray-500">
        Sua próxima renovação será em <strong>{formatDate(billing.current_period_end)}</strong>.
      </p>
    );
  }

  if (billing.status === "past_due") {
    return (
      <p className="text-sm text-red-600">
        Houve um problema com o pagamento. Atualize sua forma de pagamento para manter o acesso.
      </p>
    );
  }

  if (billing.status === "canceled") {
    return (
      <p className="text-sm text-gray-500">
        Sua assinatura foi cancelada. Assine novamente para recuperar o acesso.
      </p>
    );
  }

  return null;
}

export default function BillingPage() {
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

  const hasPlan = billing?.plan !== null && billing?.plan !== "none";
  const isPaid  = billing?.paid === true;
  const hasPortal = !!billing?.stripe_customer_id;

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-lg mx-auto px-4 py-8">
        <h1 className="text-2xl font-bold text-gray-900 mb-1">Meu Plano</h1>
        <p className="text-gray-500 text-sm mb-6">Gerencie sua assinatura EasyHealth.</p>

        {/* Status atual */}
        {billing && (
          <div className="bg-white rounded-2xl border border-gray-200 p-4 mb-6">
            <div className="flex items-center justify-between mb-2">
              <span className="font-medium text-gray-800">
                {!hasPlan
                  ? "Sem assinatura"
                  : billing.plan === "pro_yearly"
                  ? "Pro Anual"
                  : "Pro Mensal"}
              </span>
              <StatusBadge status={billing.status ?? null} />
            </div>
            <StatusMessage billing={billing} />
          </div>
        )}

        {error && (
          <div className="bg-red-50 text-red-700 rounded-xl px-4 py-3 text-sm mb-4">
            {error}
          </div>
        )}

        {/* Troca de plano — só mostra para assinantes ativos */}
        {isPaid && billing && (billing.plan === "pro_monthly" || billing.plan === "pro_yearly") && (
          <div className="mb-6">
            <h2 className="text-sm font-semibold text-gray-700 mb-3">Mudar de plano</h2>
            <div className="flex flex-col gap-3">
              {/* Mensal */}
              <div className={`bg-white rounded-2xl border-2 p-4 ${billing.plan === "pro_monthly" ? "border-primary-300 bg-primary-50" : "border-gray-100"}`}>
                <div className="flex items-center justify-between">
                  <div>
                    <h3 className="font-semibold text-gray-900 text-sm">Pro Mensal</h3>
                    <p className="text-lg font-bold text-gray-900">R$ 19,90<span className="text-xs font-normal text-gray-500">/mês</span></p>
                  </div>
                  {billing.plan === "pro_monthly" ? (
                    <span className="rounded-full bg-primary-100 px-3 py-1 text-xs font-semibold text-primary-700">Plano atual</span>
                  ) : (
                    <button
                      onClick={handlePortal}
                      disabled={actionLoading !== null}
                      className="rounded-xl bg-gray-900 px-4 py-2 text-xs font-medium text-white disabled:opacity-50 hover:bg-gray-700 transition"
                    >
                      {actionLoading === "portal" ? "..." : "Mudar para este"}
                    </button>
                  )}
                </div>
              </div>
              {/* Anual */}
              <div className={`bg-white rounded-2xl border-2 p-4 relative ${billing.plan === "pro_yearly" ? "border-primary-300 bg-primary-50" : "border-primary-200"}`}>
                {billing.plan !== "pro_yearly" && (
                  <span className="absolute -top-2.5 left-4 rounded-full bg-primary-500 px-2 py-0.5 text-xs font-bold text-white">Mais vantajoso</span>
                )}
                <div className="flex items-center justify-between">
                  <div>
                    <h3 className="font-semibold text-gray-900 text-sm">Pro Anual</h3>
                    <p className="text-lg font-bold text-gray-900">R$ 118,80<span className="text-xs font-normal text-gray-500">/ano</span></p>
                    <p className="text-xs text-green-600 font-medium">Economize ~50%</p>
                  </div>
                  {billing.plan === "pro_yearly" ? (
                    <span className="rounded-full bg-primary-100 px-3 py-1 text-xs font-semibold text-primary-700">Plano atual</span>
                  ) : (
                    <button
                      onClick={handlePortal}
                      disabled={actionLoading !== null}
                      className="rounded-xl bg-primary-500 px-4 py-2 text-xs font-medium text-white disabled:opacity-50 hover:bg-primary-600 transition"
                    >
                      {actionLoading === "portal" ? "..." : "Mudar para este"}
                    </button>
                  )}
                </div>
              </div>
            </div>
            <p className="mt-2 text-xs text-gray-400 text-center">A mudança é feita via portal seguro do Stripe</p>
          </div>
        )}

        {/* Cards de plano — só mostra se não tiver assinatura ativa */}
        {!isPaid && (
          <div className="flex flex-col gap-4 mb-6">
            {/* Pro Mensal */}
            <div className="bg-white rounded-2xl border border-gray-200 p-5">
              <div className="flex items-start justify-between mb-3">
                <div>
                  <h2 className="font-semibold text-gray-900">Pro Mensal</h2>
                  <p className="text-2xl font-bold text-gray-900 mt-1">
                    R$ 19,90<span className="text-sm font-normal text-gray-500">/mês</span>
                  </p>
                  <p className="text-xs text-gray-400">Depois de 7 dias grátis</p>
                </div>
              </div>
              <ul className="text-sm text-gray-600 space-y-1 mb-4">
                <li>✓ Acesso completo a todos os recursos</li>
                <li>✓ Treinos personalizados por IA</li>
                <li>✓ Histórico ilimitado</li>
                <li className="font-medium text-primary-700">✓ 7 dias grátis</li>
              </ul>
              <button
                onClick={() => handleCheckout("pro_monthly")}
                disabled={actionLoading !== null}
                className="w-full bg-gray-900 text-white rounded-xl py-3 text-sm font-medium disabled:opacity-50 hover:bg-gray-700 transition"
              >
                {actionLoading === "pro_monthly" ? "Aguarde..." : "Começar 7 dias grátis"}
              </button>
              <p className="text-xs text-gray-400 text-center mt-2">Cancele quando quiser</p>
            </div>

            {/* Pro Anual */}
            <div className="bg-white rounded-2xl border-2 border-primary-500 p-5 relative">
              <span className="absolute -top-3 left-1/2 -translate-x-1/2 bg-primary-500 text-white text-xs font-bold px-3 py-1 rounded-full">
                Mais vantajoso
              </span>
              <div className="flex items-start justify-between mb-3">
                <div>
                  <h2 className="font-semibold text-gray-900">Pro Anual</h2>
                  <p className="text-2xl font-bold text-gray-900 mt-1">
                    R$ 118,80<span className="text-sm font-normal text-gray-500">/ano</span>
                  </p>
                  <p className="text-sm text-primary-600 font-medium">≈ R$ 9,90/mês</p>
                  <p className="text-xs text-green-600 font-semibold">Economize cerca de 50%</p>
                </div>
              </div>
              <ul className="text-sm text-gray-600 space-y-1 mb-4">
                <li>✓ Tudo do Pro Mensal</li>
                <li>✓ Metade do preço</li>
                <li className="font-medium text-primary-700">✓ 7 dias grátis</li>
              </ul>
              <button
                onClick={() => handleCheckout("pro_yearly")}
                disabled={actionLoading !== null}
                className="w-full bg-primary-500 text-white rounded-xl py-3 text-sm font-medium disabled:opacity-50 hover:bg-primary-600 transition"
              >
                {actionLoading === "pro_yearly" ? "Aguarde..." : "Começar 7 dias grátis"}
              </button>
              <p className="text-xs text-gray-400 text-center mt-2">Cancele quando quiser</p>
            </div>
          </div>
        )}

        {/* Botões de gestão */}
        {hasPortal && (
          <div className="flex flex-col gap-3">
            <button
              onClick={handlePortal}
              disabled={actionLoading !== null}
              className="w-full border border-gray-300 text-gray-700 rounded-xl py-3 text-sm font-medium disabled:opacity-50 hover:bg-gray-50 transition"
            >
              {actionLoading === "portal" ? "Aguarde..." : "Gerenciar assinatura"}
            </button>
            {isPaid && (
              <button
                onClick={handlePortal}
                disabled={actionLoading !== null}
                className="w-full border border-gray-200 text-gray-500 rounded-xl py-3 text-sm font-medium disabled:opacity-50 hover:bg-gray-50 transition"
              >
                Cancelar ou alterar plano
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

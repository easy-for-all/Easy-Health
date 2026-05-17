"use client";

import { useState, useCallback } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { PublicLayout } from "@/shared/components/public-layout";
import { useAuth } from "@/features/auth/auth-context";
import { api, ApiError } from "@/shared/lib/api";
import { setPendingPlan, type PendingPlan } from "@/features/billing/checkout-intent";

const FEATURES = [
  "Treinos personalizados por IA",
  "Plano semanal adaptável",
  "Histórico ilimitado de treinos",
  "Troca de exercícios inteligente",
  "Acompanhamento de evolução",
  "Suporte a treinos em casa e academia",
];

function CheckIcon() {
  return (
    <svg className="w-4 h-4 text-green-500 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
    </svg>
  );
}

export default function PricingPage() {
  const { user } = useAuth();
  const router = useRouter();
  const [loadingPlan, setLoadingPlan] = useState<PendingPlan | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleSelectPlan = useCallback(async (plan: PendingPlan) => {
    setError(null);
    setLoadingPlan(plan);

    if (!user) {
      setPendingPlan(plan);
      router.push("/sign-up");
      return;
    }

    try {
      const { checkout_url } = await api.post<{ checkout_url: string }>(
        "/api/v1/billing/checkout",
        { plan }
      );
      window.location.href = checkout_url;
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Erro ao iniciar checkout. Tente novamente.");
      setLoadingPlan(null);
    }
  }, [user, router]);

  const isLoading = loadingPlan !== null;

  return (
    <PublicLayout>
      {/* Hero */}
      <section className="bg-white py-16 px-4 text-center border-b border-gray-100">
        <div className="max-w-2xl mx-auto">
          <span className="inline-block bg-primary-50 text-primary-700 text-xs font-semibold px-3 py-1 rounded-full mb-4">
            7 dias grátis — sem cartão necessário
          </span>
          <h1 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
            Treine melhor com a EasyHealth
          </h1>
          <p className="text-gray-500 text-lg mb-8">
            Monte sua rotina de treinos, acompanhe sua evolução e desbloqueie todos os recursos premium com 7 dias grátis.
          </p>
          <a
            href="#planos"
            className="inline-block bg-primary-500 text-white font-semibold px-8 py-3 rounded-xl hover:bg-primary-600 transition"
          >
            Começar 7 dias grátis
          </a>
          <p className="text-xs text-gray-400 mt-3">Cancele quando quiser. Sem compromisso.</p>
        </div>
      </section>

      {/* Plan cards */}
      <section id="planos" className="max-w-3xl mx-auto px-4 py-14">
        {error && (
          <div className="bg-red-50 text-red-700 rounded-xl px-4 py-3 text-sm mb-6 text-center">
            {error}
          </div>
        )}

        <div className="flex flex-col md:flex-row gap-6">
          {/* Pro Mensal */}
          <div className="flex-1 bg-white rounded-2xl border border-gray-200 p-6 flex flex-col">
            <h2 className="text-lg font-bold text-gray-900 mb-1">Pro Mensal</h2>
            <div className="mb-1">
              <span className="text-3xl font-extrabold text-gray-900">R$ 19,90</span>
              <span className="text-sm text-gray-500">/mês</span>
            </div>
            <p className="text-xs text-gray-400 mb-4">Depois de 7 dias grátis</p>

            <ul className="space-y-2 mb-6 flex-1">
              {FEATURES.map((f) => (
                <li key={f} className="flex items-center gap-2 text-sm text-gray-600">
                  <CheckIcon />
                  {f}
                </li>
              ))}
            </ul>

            <p className="text-xs text-gray-400 mb-3 text-center">Cancele quando quiser</p>
            <button
              onClick={() => handleSelectPlan("pro_monthly")}
              disabled={isLoading}
              className="w-full bg-gray-800 text-white rounded-xl py-3 text-sm font-semibold hover:bg-gray-900 transition disabled:opacity-50"
            >
              {loadingPlan === "pro_monthly" ? "Aguarde..." : "Começar 7 dias grátis"}
            </button>
          </div>

          {/* Pro Anual */}
          <div className="flex-1 bg-white rounded-2xl border-2 border-primary-500 p-6 flex flex-col relative">
            <span className="absolute -top-3.5 left-1/2 -translate-x-1/2 bg-primary-500 text-white text-xs font-bold px-4 py-1 rounded-full">
              Mais vantajoso
            </span>

            <h2 className="text-lg font-bold text-gray-900 mb-1">Pro Anual</h2>
            <div className="mb-1">
              <span className="text-3xl font-extrabold text-gray-900">R$ 118,80</span>
              <span className="text-sm text-gray-500">/ano</span>
            </div>
            <p className="text-sm text-primary-600 font-medium mb-0.5">≈ R$ 9,90/mês</p>
            <p className="text-xs text-green-600 font-semibold mb-4">Economize cerca de 50%</p>

            <ul className="space-y-2 mb-6 flex-1">
              <li className="flex items-center gap-2 text-sm text-gray-600">
                <CheckIcon />
                Tudo do Pro Mensal
              </li>
              {FEATURES.slice(0, 4).map((f) => (
                <li key={f} className="flex items-center gap-2 text-sm text-gray-600">
                  <CheckIcon />
                  {f}
                </li>
              ))}
            </ul>

            <p className="text-xs text-gray-400 mb-3 text-center">Cancele quando quiser</p>
            <button
              onClick={() => handleSelectPlan("pro_yearly")}
              disabled={isLoading}
              className="w-full bg-primary-500 text-white rounded-xl py-3 text-sm font-semibold hover:bg-primary-600 transition disabled:opacity-50"
            >
              {loadingPlan === "pro_yearly" ? "Aguarde..." : "Começar 7 dias grátis"}
            </button>
          </div>
        </div>

        {/* Footer note */}
        <p className="text-center text-xs text-gray-400 mt-8">
          Já tem conta?{" "}
          <Link href="/login" className="text-primary-600 hover:underline">
            Entrar
          </Link>{" "}
          para gerenciar sua assinatura.
        </p>
      </section>
    </PublicLayout>
  );
}

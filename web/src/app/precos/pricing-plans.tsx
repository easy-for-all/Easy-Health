"use client";

import { useEffect } from "react";
import Link from "next/link";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";

const PLANS = [
  {
    id: "pro_monthly",
    name: "Pro Mensal",
    price: "R$ 19,90",
    period: "/mês",
    description: "Ideal para experimentar com flexibilidade.",
    features: [
      "Treino personalizado com IA",
      "Plano semanal adaptativo",
      "Histórico completo de treinos",
      "Troca de exercícios com IA",
      "Análise de exames",
      "Suporte por e-mail",
    ],
    cta: "Começar grátis",
    highlighted: false,
  },
  {
    id: "pro_annual",
    name: "Pro Anual",
    price: "R$ 9,90",
    period: "/mês",
    badge: "Melhor custo-benefício",
    description: "R$ 118,80 cobrado anualmente. Economize 50% em relação ao mensal.",
    features: [
      "Tudo do plano mensal",
      "Economia de R$ 120/ano",
      "Prioridade no suporte",
      "Acesso antecipado a novidades",
    ],
    cta: "Começar grátis",
    highlighted: true,
  },
];

export function PricingPlans() {
  useEffect(() => { trackEvent(EVENTS.PAYWALL_VIEWED); }, []);

  return (
    <div className="grid gap-6 sm:grid-cols-2">
      {PLANS.map((plan) => (
        <div
          key={plan.name}
          className={`relative rounded-2xl border p-8 ${
            plan.highlighted
              ? "border-primary-400 bg-primary-50 shadow-lg"
              : "border-gray-200 bg-white"
          }`}
        >
          {plan.badge && (
            <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-primary-500 px-4 py-1 text-xs font-bold text-white">
              {plan.badge}
            </span>
          )}
          <p className="text-lg font-bold text-gray-900">{plan.name}</p>
          <div className="mt-2 flex items-end gap-1">
            <span className="text-4xl font-bold text-gray-900">{plan.price}</span>
            <span className="mb-1 text-gray-500">{plan.period}</span>
          </div>
          <p className="mt-2 text-sm text-gray-500">{plan.description}</p>
          <ul className="mt-6 space-y-2">
            {plan.features.map((f) => (
              <li key={f} className="flex items-start gap-2 text-sm text-gray-700">
                <span className="mt-0.5 text-primary-500">✓</span>
                {f}
              </li>
            ))}
          </ul>
          <Link
            href="/sign-up"
            onClick={() => trackEvent(EVENTS.CHECKOUT_STARTED, { plan: plan.id })}
            className={`mt-8 block w-full rounded-xl py-3 text-center text-sm font-semibold transition-colors ${
              plan.highlighted
                ? "bg-primary-500 text-white hover:bg-primary-600"
                : "border border-primary-500 text-primary-600 hover:bg-primary-50"
            }`}
          >
            {plan.cta}
          </Link>
        </div>
      ))}
    </div>
  );
}

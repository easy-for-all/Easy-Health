import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";

export const metadata: Metadata = {
  title: "Preços | EasyHealth",
  description: "Escolha o plano EasyHealth ideal para você. 7 dias grátis, sem cartão de crédito. Cancele quando quiser.",
};

const PLANS = [
  {
    name: "Pro Mensal",
    price: "R$ 19,90",
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
    name: "Pro Anual",
    price: "R$ 9,90",
    period: "/mês",
    badge: "Melhor custo-benefício",
    description: "R$ 118,80 cobrado anualmente. Economize 50% em relação ao mensal.",
    features: [
      "Tudo do plano mensal",
      "Economia de R$ 120/ano",
      "Prioridade no suporte",
      "Acesso antecipado a novidades",
    ],
    cta: "Começar grátis",
    highlighted: true,
  },
];

const FAQS = [
  {
    q: "Preciso de cartão de crédito para testar?",
    a: "Não. Os 7 dias de teste são totalmente gratuitos e sem necessidade de cartão de crédito. Você só fornece dados de pagamento se decidir continuar após o período de teste.",
  },
  {
    q: "Posso cancelar quando quiser?",
    a: "Sim. Você pode cancelar sua assinatura a qualquer momento, diretamente pelas configurações do app. Não há multa ou fidelidade.",
  },
  {
    q: "O que acontece depois dos 7 dias grátis?",
    a: "Após o período de teste, você escolhe um plano para continuar. Se não assinar, o acesso às funcionalidades premium é pausado — seus dados ficam salvos.",
  },
  {
    q: "Posso trocar de plano depois?",
    a: "Sim. Você pode fazer upgrade ou downgrade do plano a qualquer momento pelas configurações de cobrança.",
  },
];

export default function Precos() {
  return (
    <PublicLayout>
      {/* Hero */}
      <section className="mx-auto max-w-5xl px-6 py-16 text-center">
        <h1 className="text-3xl font-bold text-gray-900 sm:text-4xl">
          Planos EasyHealth
        </h1>
        <p className="mx-auto mt-4 max-w-xl text-lg text-gray-500">
          Comece com 7 dias grátis. Sem cartão de crédito. Cancele quando quiser.
        </p>
      </section>

      {/* Plans */}
      <section className="pb-20">
        <div className="mx-auto max-w-3xl px-6">
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
          <p className="mt-6 text-center text-sm text-gray-400">
            7 dias grátis incluídos em ambos os planos. Sem cobrança automática durante o teste.
          </p>
        </div>
      </section>

      {/* FAQ */}
      <section className="bg-gray-50 py-20">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Perguntas frequentes</h2>
          <div className="mt-8 space-y-6">
            {FAQS.map((faq) => (
              <div key={faq.q}>
                <p className="font-semibold text-gray-900">{faq.q}</p>
                <p className="mt-2 text-sm leading-relaxed text-gray-600">{faq.a}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA final */}
      <section className="bg-primary-500 py-16">
        <div className="mx-auto max-w-5xl px-6 text-center">
          <h2 className="text-2xl font-bold text-white">Comece hoje, sem compromisso</h2>
          <p className="mx-auto mt-3 max-w-md text-primary-100">
            7 dias grátis para testar tudo. Sem cartão de crédito para começar.
          </p>
          <Link
            href="/sign-up"
            className="mt-6 inline-block rounded-xl bg-white px-8 py-4 text-base font-semibold text-primary-600 hover:bg-primary-50"
          >
            Criar conta grátis
          </Link>
        </div>
      </section>
    </PublicLayout>
  );
}

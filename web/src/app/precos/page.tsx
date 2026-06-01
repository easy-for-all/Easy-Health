import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";
import { PricingPlans } from "./pricing-plans";

export const metadata: Metadata = {
  title: "Preços | EasyHealth",
  description: "Escolha o plano EasyHealth ideal para você. 7 dias grátis, sem cartão de crédito. Cancele quando quiser.",
};

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
        <h1 className="text-3xl font-bold text-white sm:text-4xl">
          Planos EasyHealth
        </h1>
        <p className="mx-auto mt-4 max-w-xl text-lg text-slate-400">
          Comece com 7 dias grátis. Sem cartão de crédito. Cancele quando quiser.
        </p>
      </section>

      {/* Plans */}
      <section className="pb-20">
        <div className="mx-auto max-w-3xl px-6">
          <PricingPlans />
          <p className="mt-6 text-center text-sm text-slate-500">
            7 dias grátis incluídos em ambos os planos. Sem cobrança automática durante o teste.
          </p>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-20" style={{ background: "#111827" }}>
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-white">Perguntas frequentes</h2>
          <div className="mt-8 space-y-6">
            {FAQS.map((faq) => (
              <div key={faq.q} className="border-b border-slate-800 pb-6">
                <p className="font-semibold text-white">{faq.q}</p>
                <p className="mt-2 text-sm leading-relaxed text-slate-400">{faq.a}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA final */}
      <section className="py-16" style={{ background: "linear-gradient(150deg, #2563eb, #1d4ed8)" }}>
        <div className="mx-auto max-w-5xl px-6 text-center">
          <h2 className="text-2xl font-bold text-white">Comece hoje, sem compromisso</h2>
          <p className="mx-auto mt-3 max-w-md text-blue-100">
            7 dias grátis para testar tudo. Sem cartão de crédito para começar.
          </p>
          <Link
            href="/sign-up"
            className="mt-6 inline-block rounded-full bg-white px-8 py-4 text-base font-semibold text-primary-700 hover:bg-blue-50"
          >
            Criar conta grátis
          </Link>
        </div>
      </section>
    </PublicLayout>
  );
}

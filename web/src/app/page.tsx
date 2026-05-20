import Link from "next/link";
import type { Metadata } from "next";
import { Footer } from "@/shared/components/footer";
import { FeatureCard } from "@/shared/components/feature-card";

export const metadata: Metadata = {
  title: "EasyHealth — Treino inteligente com IA",
  description: "A EasyHealth cria treinos personalizados com IA, acompanha sua evolução e ajuda você a manter uma rotina fitness mais inteligente.",
};

const FEATURES = [
  {
    icon: "🤖",
    title: "IA para treino",
    description: "Receba sugestões de treino com base no seu objetivo, rotina e evolução.",
    href: "/ia-para-treino",
  },
  {
    icon: "📋",
    title: "Treino personalizado",
    description: "Planos ajustados ao seu nível, frequência e disponibilidade.",
    href: "/treino-personalizado",
  },
  {
    icon: "🔥",
    title: "Emagrecimento",
    description: "Organize uma rotina de treino focada em perda de gordura e consistência.",
    href: "/emagrecimento",
  },
  {
    icon: "🏠",
    title: "Treino em casa",
    description: "Treinos possíveis mesmo sem academia, com exercícios adaptados ao seu contexto.",
    href: "/treino-em-casa",
  },
  {
    icon: "🩺",
    title: "Análise de exames",
    description: "Use seus dados de saúde para apoiar uma jornada fitness mais personalizada.",
    href: "/analise-de-exames",
  },
  {
    icon: "💳",
    title: "Preços",
    description: "Escolha o plano ideal para começar sua evolução.",
    href: "/precos",
  },
];

export default function LandingPage() {
  return (
    <div className="flex min-h-screen flex-col bg-white">
      {/* Header */}
      <header className="sticky top-0 z-10 border-b border-gray-100 bg-white/90 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-4">
          <div className="flex items-center gap-2">
            <img src="/logo.png" alt="EasyHealth" className="h-10 w-auto" />
            <span className="text-xl font-bold text-primary-600">EasyHealth</span>
          </div>
          <nav className="flex items-center gap-3">
            <Link href="/precos" className="hidden text-sm font-medium text-gray-600 hover:text-gray-900 sm:block">
              Preços
            </Link>
            <Link href="/login" className="text-sm font-medium text-gray-600 hover:text-gray-900">
              Entrar
            </Link>
            <Link href="/sign-up" className="rounded-lg bg-primary-500 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-600">
              Criar conta
            </Link>
          </nav>
        </div>
      </header>

      <main className="flex-1">
        {/* Hero */}
        <section className="mx-auto max-w-5xl px-6 py-20 text-center">
          <h1 className="text-4xl font-bold leading-tight text-gray-900 sm:text-5xl">
            Treino inteligente com IA<br />
            <span className="text-primary-500">para evoluir com mais constância.</span>
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-lg text-gray-500">
            A EasyHealth cria treinos personalizados, acompanha sua evolução e ajuda você a manter uma rotina fitness mais inteligente.
          </p>
          <div className="mt-8 flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
            <Link href="/sign-up" className="w-full rounded-xl bg-primary-500 px-8 py-4 text-base font-semibold text-white hover:bg-primary-600 sm:w-auto">
              Começar agora
            </Link>
            <Link href="#como-funciona" className="w-full rounded-xl border border-gray-200 px-8 py-4 text-base font-semibold text-gray-700 hover:bg-gray-50 sm:w-auto">
              Ver como funciona
            </Link>
          </div>
        </section>

        {/* Como funciona — Feature cards */}
        <section id="como-funciona" className="bg-gray-50 py-20">
          <div className="mx-auto max-w-5xl px-6">
            <div className="mb-12 text-center">
              <h2 className="text-3xl font-bold text-gray-900">O que a EasyHealth faz por você</h2>
              <p className="mt-4 text-gray-500">Ferramentas de IA para tornar sua rotina fitness mais simples e eficaz.</p>
            </div>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {FEATURES.map((f) => (
                <FeatureCard key={f.href} {...f} />
              ))}
            </div>
          </div>
        </section>

        {/* Sobre */}
        <section className="bg-primary-50 py-20">
          <div className="mx-auto max-w-5xl px-6">
            <div className="mx-auto max-w-2xl text-center">
              <h2 className="text-3xl font-bold text-gray-900">Feito para quem quer evoluir de verdade</h2>
              <p className="mt-4 leading-relaxed text-gray-600">
                Somos um time apaixonado por saúde e tecnologia. A EasyHealth foi criada para tornar a rotina fitness mais simples, inteligente e adaptável — seja você iniciante ou avançado.
              </p>
              <div className="mt-10 grid gap-6 sm:grid-cols-3">
                <div className="rounded-2xl bg-white p-6 text-center shadow-sm">
                  <p className="text-3xl">🎯</p>
                  <p className="mt-3 font-semibold text-gray-900">Foco no que importa</p>
                  <p className="mt-2 text-sm text-gray-500">Só o treino que você precisa fazer hoje.</p>
                </div>
                <div className="rounded-2xl bg-white p-6 text-center shadow-sm">
                  <p className="text-3xl">📈</p>
                  <p className="mt-3 font-semibold text-gray-900">Evolução visível</p>
                  <p className="mt-2 text-sm text-gray-500">Registre cargas e acompanhe seu progresso semana a semana.</p>
                </div>
                <div className="rounded-2xl bg-white p-6 text-center shadow-sm">
                  <p className="text-3xl">🔄</p>
                  <p className="mt-3 font-semibold text-gray-900">Adaptável ao seu ritmo</p>
                  <p className="mt-2 text-sm text-gray-500">Troque exercícios, ajuste cargas e siga no seu ritmo.</p>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* CTA final */}
        <section className="bg-primary-500 py-20">
          <div className="mx-auto max-w-5xl px-6 text-center">
            <h2 className="text-3xl font-bold text-white">Comece hoje com 7 dias grátis</h2>
            <p className="mx-auto mt-4 max-w-xl text-lg text-primary-100">Sem cartão de crédito para começar. Cancele quando quiser.</p>
            <Link href="/sign-up" className="mt-8 inline-block rounded-xl bg-white px-8 py-4 text-base font-semibold text-primary-600 hover:bg-primary-50">
              Criar conta grátis
            </Link>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}

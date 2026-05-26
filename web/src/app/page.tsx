import Link from "next/link";
import type { Metadata } from "next";
import { Footer } from "@/shared/components/footer";
import { FeatureCard } from "@/shared/components/feature-card";
import { HeroCta } from "@/shared/components/hero-cta";
import { AnalyticsTracker } from "@/shared/components/analytics-tracker";

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
    <div className="flex min-h-screen flex-col bg-white dark:bg-gray-950">
      <AnalyticsTracker eventName="landing_view" />
      <AnalyticsTracker eventName="screen_view" params={{ screen_name: "home" }} />
      {/* Header */}
      <header className="sticky top-0 z-10 border-b border-gray-100 bg-white/90 backdrop-blur dark:border-gray-800 dark:bg-gray-950/90">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-4">
          <div className="flex items-center gap-2">
            <img src="/logo.png" alt="EasyHealth" className="h-10 w-auto" />
            <span className="text-xl font-bold text-primary-600">EasyHealth</span>
          </div>
          <nav className="flex items-center gap-3">
            <Link href="/precos" className="hidden text-sm font-medium text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100 sm:block">
              Preços
            </Link>
            <Link href="/login" className="text-sm font-medium text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100">
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
          <div className="mb-5 inline-flex items-center gap-2 rounded-full bg-primary-50 px-4 py-1.5 text-sm font-medium text-primary-700 dark:bg-primary-950/40 dark:text-primary-300">
            <span className="text-primary-500">✓</span>
            Mais de 500 treinos gerados · Grátis por 7 dias
          </div>
          <h1 className="text-4xl font-bold leading-tight text-gray-900 dark:text-gray-50 sm:text-5xl">
            Treino inteligente com IA<br />
            <span className="text-primary-500">para evoluir com mais constância.</span>
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-lg text-gray-500 dark:text-gray-400">
            A EasyHealth cria treinos personalizados, acompanha sua evolução e ajuda você a manter uma rotina fitness mais inteligente.
          </p>
          <div className="mt-8 flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
            <HeroCta />
            <Link href="#como-funciona" className="w-full rounded-xl border border-gray-200 px-8 py-4 text-base font-semibold text-gray-700 hover:bg-gray-50 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-800 sm:w-auto">
              Ver como funciona
            </Link>
          </div>
          <p className="mt-6 text-sm italic text-gray-400 dark:text-gray-500">
            "Em 2 semanas já sabia exatamente o que treinar todo dia." — Lucas M.
          </p>
        </section>

        {/* Como funciona — Feature cards */}
        <section id="como-funciona" className="bg-gray-50 py-20 dark:bg-gray-900">
          <div className="mx-auto max-w-5xl px-6">
            <div className="mb-12 text-center">
              <h2 className="text-3xl font-bold text-gray-900 dark:text-gray-50">O que a EasyHealth faz por você</h2>
              <p className="mt-4 text-gray-500 dark:text-gray-400">Ferramentas de IA para tornar sua rotina fitness mais simples e eficaz.</p>
            </div>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {FEATURES.map((f) => (
                <FeatureCard key={f.href} {...f} />
              ))}
            </div>
          </div>
        </section>

        {/* Como funciona na prática */}
        <section className="py-20">
          <div className="mx-auto max-w-5xl px-6">
            <div className="mb-12 text-center">
              <h2 className="text-3xl font-bold text-gray-900 dark:text-gray-50">Como funciona na prática</h2>
              <p className="mt-4 text-gray-500 dark:text-gray-400">Veja o que você terá acesso ao entrar na plataforma.</p>
            </div>
            <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {/* Card 1: IA gera seu treino */}
              <div className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                <div className="mb-3 flex items-center gap-2">
                  <span className="flex h-8 w-8 items-center justify-center rounded-full bg-primary-100 text-sm">🤖</span>
                  <span className="text-xs font-semibold uppercase tracking-wide text-primary-600">IA gera seu treino</span>
                </div>
                <div className="space-y-2 rounded-xl bg-gray-50 p-3">
                  <div className="flex items-center justify-between rounded-lg bg-white px-3 py-2 shadow-sm">
                    <span className="text-xs font-medium text-gray-700">Supino Reto</span>
                    <span className="text-xs text-gray-400">4 × 10</span>
                  </div>
                  <div className="flex items-center justify-between rounded-lg bg-white px-3 py-2 shadow-sm">
                    <span className="text-xs font-medium text-gray-700">Remada Curvada</span>
                    <span className="text-xs text-gray-400">3 × 12</span>
                  </div>
                  <div className="flex items-center justify-between rounded-lg bg-white px-3 py-2 shadow-sm">
                    <span className="text-xs font-medium text-gray-700">Agachamento Livre</span>
                    <span className="text-xs text-gray-400">4 × 8</span>
                  </div>
                </div>
                <p className="mt-3 text-xs text-gray-500">Plano personalizado gerado em segundos com base no seu perfil.</p>
              </div>

              {/* Card 2: Treino do dia */}
              <div className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                <div className="mb-3 flex items-center gap-2">
                  <span className="flex h-8 w-8 items-center justify-center rounded-full bg-green-100 text-sm">💪</span>
                  <span className="text-xs font-semibold uppercase tracking-wide text-green-600">Treino do dia</span>
                </div>
                <div className="rounded-xl bg-gradient-to-br from-primary-500 to-primary-700 p-4 text-white">
                  <p className="text-xs font-semibold uppercase tracking-wide text-primary-200">Hoje · Treino A</p>
                  <p className="mt-1 text-lg font-bold">Peito + Tríceps</p>
                  <p className="mt-1 text-xs text-primary-100">6 exercícios · ~50 min</p>
                  <div className="mt-3 inline-flex items-center gap-1.5 rounded-full bg-white px-3 py-1.5 text-xs font-semibold text-primary-600">
                    Iniciar treino →
                  </div>
                </div>
                <p className="mt-3 text-xs text-gray-500">Sabe exatamente o que fazer a cada dia sem precisar pensar.</p>
              </div>

              {/* Card 3: Histórico e evolução */}
              <div className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                <div className="mb-3 flex items-center gap-2">
                  <span className="flex h-8 w-8 items-center justify-center rounded-full bg-blue-100 text-sm">📈</span>
                  <span className="text-xs font-semibold uppercase tracking-wide text-blue-600">Evolução</span>
                </div>
                <div className="space-y-2 rounded-xl bg-gray-50 p-3">
                  {[
                    { label: "Supino", value: "80 kg", change: "+5 kg", up: true },
                    { label: "Agachamento", value: "100 kg", change: "+10 kg", up: true },
                    { label: "Corrida", value: "5,2 km", change: "+0,4 km", up: true },
                  ].map((item) => (
                    <div key={item.label} className="flex items-center justify-between rounded-lg bg-white px-3 py-2 shadow-sm">
                      <span className="text-xs font-medium text-gray-700">{item.label}</span>
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-semibold text-gray-900">{item.value}</span>
                        <span className="text-xs font-medium text-green-600">{item.change}</span>
                      </div>
                    </div>
                  ))}
                </div>
                <p className="mt-3 text-xs text-gray-500">Acompanhe sua evolução semana a semana com registros automáticos.</p>
              </div>

              {/* Card 4: Adaptação com IA */}
              <div className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                <div className="mb-3 flex items-center gap-2">
                  <span className="flex h-8 w-8 items-center justify-center rounded-full bg-orange-100 text-sm">🔄</span>
                  <span className="text-xs font-semibold uppercase tracking-wide text-orange-600">Adaptação IA</span>
                </div>
                <div className="rounded-xl bg-orange-50 p-3">
                  <div className="flex items-start gap-2">
                    <span className="mt-0.5 text-base">✨</span>
                    <div>
                      <p className="text-xs font-semibold text-orange-800">Sugestão da IA</p>
                      <p className="mt-1 text-xs text-orange-700">
                        Você relatou dor no ombro. Sugiro substituir o desenvolvimento militar por elevação lateral por 2 semanas.
                      </p>
                    </div>
                  </div>
                  <button className="mt-3 w-full rounded-lg bg-orange-500 py-2 text-xs font-semibold text-white">Aplicar sugestão</button>
                </div>
                <p className="mt-3 text-xs text-gray-500">A IA ajusta seu treino com base no seu feedback e histórico.</p>
              </div>

              {/* Card 5: Academia, casa ou cardio */}
              <div className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                <div className="mb-3 flex items-center gap-2">
                  <span className="flex h-8 w-8 items-center justify-center rounded-full bg-purple-100 text-sm">🏃</span>
                  <span className="text-xs font-semibold uppercase tracking-wide text-purple-600">Seu contexto</span>
                </div>
                <div className="grid grid-cols-3 gap-2">
                  {[
                    { icon: "🏋️", label: "Academia" },
                    { icon: "🏠", label: "Em casa" },
                    { icon: "❤️", label: "Cardio" },
                  ].map((ctx) => (
                    <div key={ctx.label} className="flex flex-col items-center gap-1.5 rounded-xl bg-gray-50 py-3 text-center">
                      <span className="text-xl">{ctx.icon}</span>
                      <span className="text-xs font-medium text-gray-700">{ctx.label}</span>
                    </div>
                  ))}
                </div>
                <p className="mt-3 text-xs text-gray-500">Treinos adaptados para academia, casa ou cardio conforme o seu dia.</p>
              </div>

              {/* Card 6: Troca de exercício */}
              <div className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                <div className="mb-3 flex items-center gap-2">
                  <span className="flex h-8 w-8 items-center justify-center rounded-full bg-teal-100 text-sm">⇄</span>
                  <span className="text-xs font-semibold uppercase tracking-wide text-teal-600">Troca rápida</span>
                </div>
                <div className="space-y-2 rounded-xl bg-gray-50 p-3">
                  <div className="flex items-center gap-2 rounded-lg bg-white px-3 py-2 shadow-sm opacity-50 line-through">
                    <span className="text-xs text-gray-500">Supino Inclinado</span>
                  </div>
                  <div className="flex items-center justify-center py-1">
                    <span className="text-xs text-teal-500">↕ trocado pela IA</span>
                  </div>
                  <div className="flex items-center gap-2 rounded-lg bg-teal-50 px-3 py-2 ring-1 ring-teal-300">
                    <span className="text-xs font-semibold text-teal-800">Crucifixo com Halteres</span>
                  </div>
                </div>
                <p className="mt-3 text-xs text-gray-500">Troque qualquer exercício com um clique. A IA sugere a melhor alternativa.</p>
              </div>
            </div>
          </div>
        </section>

        {/* Sobre */}
        <section className="bg-primary-50 py-20 dark:bg-primary-950/30">
          <div className="mx-auto max-w-5xl px-6">
            <div className="mx-auto max-w-2xl text-center">
              <h2 className="text-3xl font-bold text-gray-900 dark:text-gray-50">Feito para quem quer evoluir de verdade</h2>
              <p className="mt-4 leading-relaxed text-gray-600 dark:text-gray-400">
                Somos um time apaixonado por saúde e tecnologia. A EasyHealth foi criada para tornar a rotina fitness mais simples, inteligente e adaptável — seja você iniciante ou avançado.
              </p>
              <div className="mt-10 grid gap-6 sm:grid-cols-3">
                <div className="rounded-2xl bg-white p-6 text-center shadow-sm dark:bg-gray-900">
                  <p className="text-3xl">🎯</p>
                  <p className="mt-3 font-semibold text-gray-900 dark:text-gray-50">Foco no que importa</p>
                  <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">Só o treino que você precisa fazer hoje.</p>
                </div>
                <div className="rounded-2xl bg-white p-6 text-center shadow-sm dark:bg-gray-900">
                  <p className="text-3xl">📈</p>
                  <p className="mt-3 font-semibold text-gray-900 dark:text-gray-50">Evolução visível</p>
                  <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">Registre cargas e acompanhe seu progresso semana a semana.</p>
                </div>
                <div className="rounded-2xl bg-white p-6 text-center shadow-sm dark:bg-gray-900">
                  <p className="text-3xl">🔄</p>
                  <p className="mt-3 font-semibold text-gray-900 dark:text-gray-50">Adaptável ao seu ritmo</p>
                  <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">Troque exercícios, ajuste cargas e siga no seu ritmo.</p>
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

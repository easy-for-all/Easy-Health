import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Agachamento: Como Fazer Corretamente | EasyHealth",
  description: "Aprenda a executar o agachamento com técnica perfeita. Músculos trabalhados, passo a passo e erros comuns para evitar lesões.",
};

export default function Agachamento() {
  return (
    <PublicLayout>
      {/* Header do exercício */}
      <section className="mx-auto max-w-3xl px-6 py-16">
        <Link href="/exercicios" className="text-sm text-primary-500 hover:underline">
          ← Todos os exercícios
        </Link>
        <h1 className="mt-4 text-3xl font-bold text-gray-900 sm:text-4xl">Agachamento</h1>
        <p className="mt-4 text-lg leading-relaxed text-gray-600">
          Considerado o rei dos exercícios para membros inferiores. Trabalha múltiplos grupos musculares ao mesmo tempo e é essencial em qualquer programa de treino de pernas.
        </p>
        <div className="mt-4 flex flex-wrap gap-2">
          <span className="rounded-full bg-primary-100 px-3 py-1 text-sm font-medium text-primary-700">Quadríceps</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Glúteos</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Posteriores de coxa</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Core</span>
        </div>
      </section>

      {/* Como executar */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Como executar</h2>
          <ol className="mt-6 space-y-4">
            {[
              "Fique em pé com os pés na largura dos ombros ou um pouco mais abertos, com os pés levemente voltados para fora.",
              "Se usar barra, apoie-a na parte superior das costas (trapézio) com pegada confortável.",
              "Inicie o movimento empurrando os quadris levemente para trás e dobrando os joelhos ao mesmo tempo.",
              "Desça até que as coxas fiquem paralelas ao chão ou um pouco abaixo, mantendo o tronco reto.",
              "Os joelhos devem acompanhar a direção dos pés — não devem fechar para dentro.",
              "Suba empurrando o chão com os pés, estendendo quadris e joelhos simultaneamente. Expire no esforço.",
            ].map((step, i) => (
              <li key={i} className="flex gap-4">
                <span className="flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full bg-primary-100 text-sm font-bold text-primary-700">
                  {i + 1}
                </span>
                <p className="text-gray-700">{step}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* Erros comuns */}
      <section className="py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Erros comuns</h2>
          <ul className="mt-6 space-y-3">
            {[
              "Joelhos colapsando para dentro (valgo) — sinal de fraqueza dos glúteos e adutores.",
              "Tronco muito inclinado para frente — pode indicar encurtamento de tornozelo ou fraqueza no core.",
              "Calcanhar levantando do chão — falta de mobilidade de tornozelo.",
              "Profundidade insuficiente — amplitude parcial reduz recrutamento de glúteos e posteriores.",
              "Olhar para baixo — mantenha o olhar neutro ou levemente acima do horizonte.",
            ].map((err) => (
              <li key={err} className="flex items-start gap-3 text-gray-700">
                <span className="mt-0.5 text-red-400">✕</span>
                {err}
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* Quando usar */}
      <section className="bg-primary-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Quando usar no treino</h2>
          <p className="mt-4 leading-relaxed text-gray-600">
            O agachamento é normalmente o primeiro exercício do dia de pernas por ser o mais exigente. Pode ser feito com barra livre, halteres, na máquina Smith ou com peso corporal para iniciantes.
          </p>
          <p className="mt-4 leading-relaxed text-gray-600">
            Para hipertrofia, 3 a 4 séries de 8 a 12 repetições. Para força máxima, 4 a 6 séries de 3 a 6 repetições com descanso longo entre séries.
          </p>
        </div>
      </section>

      <CTASection
        title="Crie um treino de pernas completo"
        subtitle="A IA da EasyHealth monta um plano personalizado para o seu nível e objetivo."
        ctaText="Criar meu treino com IA"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}

import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Leg Press: Como Fazer Corretamente | EasyHealth",
  description: "Aprenda a executar o leg press com técnica perfeita. Músculos trabalhados, passo a passo e erros comuns para evitar lesões.",
};

export default function LegPress() {
  return (
    <PublicLayout>
      {/* Header do exercício */}
      <section className="mx-auto max-w-3xl px-6 py-16">
        <Link href="/exercicios" className="text-sm text-primary-500 hover:underline">
          ← Todos os exercícios
        </Link>
        <h1 className="mt-4 text-3xl font-bold text-gray-900 sm:text-4xl">Leg Press</h1>
        <p className="mt-4 text-lg leading-relaxed text-gray-600">
          Uma das máquinas mais populares para pernas. Permite trabalhar quadríceps, glúteos e posteriores com carga elevada e menor exigência de estabilização em comparação ao agachamento livre.
        </p>
        <div className="mt-4 flex flex-wrap gap-2">
          <span className="rounded-full bg-primary-100 px-3 py-1 text-sm font-medium text-primary-700">Quadríceps</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Glúteos</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Posteriores de coxa</span>
        </div>
      </section>

      {/* Como executar */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Como executar</h2>
          <ol className="mt-6 space-y-4">
            {[
              "Sente-se na máquina com as costas e a cabeça completamente apoiadas no encosto. Ajuste o encosto para que os joelhos formem aproximadamente 90° com os pés na plataforma.",
              "Posicione os pés na plataforma na largura dos ombros, com os pés levemente voltados para fora.",
              "Destrave a máquina e comece a descer a plataforma de forma controlada, fletindo os joelhos.",
              "Desça até que os joelhos formem aproximadamente 90° (ou um ângulo confortável) sem que os glúteos saiam do banco.",
              "Empurre a plataforma de volta para a posição inicial estendendo os joelhos, mas sem travá-los completamente no topo.",
              "Mantenha os pés planos na plataforma durante todo o movimento — não deixe os calcanhares levantarem.",
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
              "Glúteos saindo do banco ao descer — indica amplitude excessiva para a flexibilidade atual ou posição inadequada dos pés.",
              "Travar os joelhos no topo — sobrecarrega a articulação sem benefício adicional.",
              "Joelhos colapsando para dentro durante o movimento.",
              "Apoiar as mãos nos joelhos para ajudar no esforço — retira tensão das pernas.",
              "Pés muito altos na plataforma e descer demais — pode causar desconforto na lombar.",
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
            O leg press é frequentemente usado como segundo exercício no dia de pernas, após o agachamento livre. Também é uma boa opção principal para quem tem restrições de coluna ou ainda está aprendendo a técnica do agachamento.
          </p>
          <p className="mt-4 leading-relaxed text-gray-600">
            A posição dos pés na plataforma muda o foco muscular: pés mais altos recrutam mais glúteos e posteriores; pés mais baixos e próximos enfatizam o quadríceps. Para hipertrofia, 3 a 5 séries de 8 a 15 repetições.
          </p>
        </div>
      </section>

      <CTASection
        title="Monte um treino de pernas completo"
        subtitle="A IA da EasyHealth cria um plano personalizado para o seu nível e objetivo."
        ctaText="Criar meu treino com IA"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}

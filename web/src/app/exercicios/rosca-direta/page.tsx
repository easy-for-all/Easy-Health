import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Rosca Direta: Como Fazer Corretamente | EasyHealth",
  description: "Aprenda a executar a rosca direta com técnica perfeita. Músculos trabalhados, passo a passo e erros comuns para evitar lesões.",
};

export default function RoscaDireta() {
  return (
    <PublicLayout>
      {/* Header do exercício */}
      <section className="mx-auto max-w-3xl px-6 py-16">
        <Link href="/exercicios" className="text-sm text-primary-500 hover:underline">
          ← Todos os exercícios
        </Link>
        <h1 className="mt-4 text-3xl font-bold text-gray-900 sm:text-4xl">Rosca Direta</h1>
        <p className="mt-4 text-lg leading-relaxed text-gray-600">
          O exercício isolador mais popular para bíceps. Simples de executar, mas fácil de fazer errado. Dominar a técnica é essencial para evitar compensações e maximizar o resultado.
        </p>
        <div className="mt-4 flex flex-wrap gap-2">
          <span className="rounded-full bg-primary-100 px-3 py-1 text-sm font-medium text-primary-700">Bíceps braquial</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Braquiorradial</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Braquial</span>
        </div>
      </section>

      {/* Como executar */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Como executar</h2>
          <ol className="mt-6 space-y-4">
            {[
              "Fique em pé com os pés na largura dos quadris, segurando a barra ou halteres com pegada supinada (palmas para cima).",
              "Mantenha os cotovelos fixos e próximos ao corpo durante todo o movimento — eles não devem avançar para frente.",
              "Flexione os cotovelos levantando o peso em direção aos ombros, expirando durante o esforço.",
              "Na fase final, contraia o bíceps ao máximo sem levar os cotovelos para frente.",
              "Desça o peso de forma lenta e controlada (fase excêntrica) até a extensão quase completa dos braços.",
              "Mantenha o tronco reto e evite balançar o corpo para ajudar no movimento.",
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
              "Balançar o tronco para trás para ajudar na subida — isso retira a tensão do bíceps.",
              "Cotovelos avançando para frente no topo do movimento — perde o isolamento.",
              "Descer o peso de forma rápida e sem controle — a fase excêntrica é igualmente importante.",
              "Amplitude parcial — não estender o braço completamente reduz o trabalho do músculo.",
              "Punhos dobrados para trás — mantenha os punhos neutros para evitar sobrecarga.",
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
            A rosca direta é um exercício isolador — geralmente usada no final do treino de costas ou bíceps, após os exercícios compostos. Pode ser feita com barra reta, barra W (EZ) ou halteres.
          </p>
          <p className="mt-4 leading-relaxed text-gray-600">
            Para hipertrofia, 3 a 4 séries de 8 a 15 repetições com foco no controle da descida. A barra W é uma opção para quem sente desconforto no pulso com a barra reta.
          </p>
        </div>
      </section>

      <CTASection
        title="Monte um treino de braços completo"
        subtitle="A IA da EasyHealth cria um plano com os exercícios certos para o seu nível."
        ctaText="Criar meu treino com IA"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}

import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Puxada Frontal: Como Fazer Corretamente | EasyHealth",
  description: "Aprenda a executar a puxada frontal com técnica perfeita. Músculos trabalhados, passo a passo e erros comuns para evitar lesões.",
};

export default function PuxadaFrontal() {
  return (
    <PublicLayout>
      {/* Header do exercício */}
      <section className="mx-auto max-w-3xl px-6 py-16">
        <Link href="/exercicios" className="text-sm text-primary-500 hover:underline">
          ← Todos os exercícios
        </Link>
        <h1 className="mt-4 text-3xl font-bold text-gray-900 sm:text-4xl">Puxada Frontal</h1>
        <p className="mt-4 text-lg leading-relaxed text-gray-600">
          Exercício fundamental para o desenvolvimento das costas. Excelente alternativa para quem ainda não consegue fazer barra fixa com o próprio peso.
        </p>
        <div className="mt-4 flex flex-wrap gap-2">
          <span className="rounded-full bg-primary-100 px-3 py-1 text-sm font-medium text-primary-700">Latíssimo do dorso</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Bíceps</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Romboides</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Trapézio inferior</span>
        </div>
      </section>

      {/* Como executar */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Como executar</h2>
          <ol className="mt-6 space-y-4">
            {[
              "Sente-se na polia alta e fixe os joelhos sob o suporte. Segure a barra com pegada pronada (palmas para frente), mais larga que os ombros.",
              "Incline levemente o tronco para trás (10 a 15°) e retraia as escápulas antes de iniciar o movimento.",
              "Puxe a barra em direção à parte superior do peito, levando os cotovelos para baixo e para os lados.",
              "No ponto final, as escápulas devem estar retraídas e deprimidas (para baixo e para dentro).",
              "Volte à posição inicial de forma controlada, estendendo os braços completamente para trabalhar a amplitude total.",
              "Mantenha o core firme durante todo o movimento para evitar compensações com o tronco.",
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
              "Puxar com os braços em vez de iniciar com as escápulas — perde o recrutamento do dorsal.",
              "Inclinar demais o tronco para trás, transformando o exercício em um remada.",
              "Não completar a amplitude — interromper o movimento antes dos braços estarem totalmente estendidos.",
              "Usar carga excessiva e balançar o corpo para auxiliar no movimento.",
              "Puxar a barra atrás do pescoço — posição que sobrecarrega a cervical.",
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
            A puxada frontal é normalmente o primeiro ou segundo exercício do dia de costas. É um excelente ponto de partida para iniciantes e intermediários que buscam desenvolver o latíssimo.
          </p>
          <p className="mt-4 leading-relaxed text-gray-600">
            Para hipertrofia, 3 a 4 séries de 8 a 12 repetições com controle na fase excêntrica. Pode ser feita com pegada pronada (mais larga) para maior trabalho do dorsal, ou supinada (mais fechada) para maior ativação do bíceps.
          </p>
        </div>
      </section>

      <CTASection
        title="Monte um treino de costas completo"
        subtitle="A IA da EasyHealth cria um plano personalizado para o seu nível e objetivo."
        ctaText="Criar meu treino com IA"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}

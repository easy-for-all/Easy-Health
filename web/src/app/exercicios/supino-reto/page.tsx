import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Supino Reto: Como Fazer Corretamente | EasyHealth",
  description: "Aprenda a executar o supino reto com técnica perfeita. Músculos trabalhados, passo a passo e erros comuns para evitar lesões.",
};

export default function SupinoReto() {
  return (
    <PublicLayout>
      {/* Header do exercício */}
      <section className="mx-auto max-w-3xl px-6 py-16">
        <Link href="/exercicios" className="text-sm text-primary-500 hover:underline">
          ← Todos os exercícios
        </Link>
        <h1 className="mt-4 text-3xl font-bold text-gray-900 sm:text-4xl">Supino Reto</h1>
        <p className="mt-4 text-lg leading-relaxed text-gray-600">
          O exercício mais clássico para o desenvolvimento do peitoral. Executado com barra ou halteres no banco reto, é base de qualquer programa de musculação.
        </p>
        <div className="mt-4 flex flex-wrap gap-2">
          <span className="rounded-full bg-primary-100 px-3 py-1 text-sm font-medium text-primary-700">Peitoral maior</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Deltoides anterior</span>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">Tríceps</span>
        </div>
      </section>

      {/* Como executar */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Como executar</h2>
          <ol className="mt-6 space-y-4">
            {[
              "Deite no banco reto com os pés apoiados no chão. A região lombar deve ter uma leve arqueada natural.",
              "Segure a barra com pegada ligeiramente mais larga que a largura dos ombros, polegar envolto na barra.",
              "Retire a barra do suporte com os braços estendidos acima do peito (não do rosto).",
              "Desça a barra de forma controlada até tocar levemente o peito na altura dos mamilos.",
              "Empurre a barra para cima em linha reta, expirando no esforço. Não trave os cotovelos no topo.",
              "Mantenha as escápulas retraídas e os ombros firmes no banco durante todo o movimento.",
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
              "Retirar os glúteos do banco durante a execução — isso sobrecarrega a lombar.",
              "Descer a barra muito acima do peito, próximo à garganta — risco de lesão no ombro.",
              "Usar carga excessiva e reduzir a amplitude do movimento.",
              "Cotovelos muito abertos (90°) — prefira entre 45° e 75° para proteger os ombros.",
              "Segurar a barra sem o polegar enrolado — risco de deixar a barra cair.",
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
            O supino reto é geralmente o primeiro exercício do dia de peito, quando a musculatura ainda está fresca para trabalhar com maior carga. Pode ser feito com barra (mais carga) ou halteres (maior amplitude e ativação estabilizadora).
          </p>
          <p className="mt-4 leading-relaxed text-gray-600">
            Para hipertrofia, faixas de 3 a 5 séries de 6 a 12 repetições são as mais indicadas. Para força, trabalhe entre 3 e 6 repetições com descanso de 3 a 5 minutos entre séries.
          </p>
        </div>
      </section>

      <CTASection
        title="Crie um treino com supino reto"
        subtitle="A IA da EasyHealth monta um plano completo de peito para o seu nível e objetivo."
        ctaText="Criar meu treino com IA"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}

import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Exercícios: Como Fazer Corretamente | EasyHealth",
  description: "Guias completos de execução dos principais exercícios de musculação. Aprenda a técnica certa e evite lesões.",
};

const EXERCISES = [
  {
    slug: "supino-reto",
    name: "Supino Reto",
    muscle: "Peitoral",
    description: "O exercício mais clássico para o desenvolvimento do peitoral. Trabalha peitoral maior, deltoides anteriores e tríceps.",
  },
  {
    slug: "agachamento",
    name: "Agachamento",
    muscle: "Quadríceps",
    description: "O rei dos exercícios para membros inferiores. Trabalha quadríceps, glúteos, posteriores de coxa e core.",
  },
  {
    slug: "puxada-frontal",
    name: "Puxada Frontal",
    muscle: "Dorsais",
    description: "Exercício fundamental para desenvolvimento das costas. Trabalha latíssimo do dorso, bíceps e romboides.",
  },
  {
    slug: "rosca-direta",
    name: "Rosca Direta",
    muscle: "Bíceps",
    description: "Exercício isolador clássico para bíceps. Trabalha bíceps braquial e braquiorradial.",
  },
  {
    slug: "leg-press",
    name: "Leg Press",
    muscle: "Quadríceps",
    description: "Alternativa ao agachamento com carga mais controlada. Trabalha quadríceps, glúteos e posteriores de coxa.",
  },
];

export default function Exercicios() {
  return (
    <PublicLayout>
      {/* Hero */}
      <section className="mx-auto max-w-3xl px-6 py-16 text-center">
        <h1 className="text-3xl font-bold text-gray-900 sm:text-4xl">
          Como executar os principais exercícios corretamente
        </h1>
        <p className="mx-auto mt-4 max-w-xl text-lg text-gray-500">
          Guias práticos de execução, músculos trabalhados e erros comuns para os exercícios mais importantes da musculação.
        </p>
      </section>

      {/* Exercise grid */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <div className="grid gap-4 sm:grid-cols-2">
            {EXERCISES.map((ex) => (
              <Link
                key={ex.slug}
                href={`/exercicios/${ex.slug}`}
                className="group rounded-xl border border-gray-100 bg-white p-6 transition-shadow hover:shadow-md"
              >
                <span className="inline-block rounded-full bg-primary-50 px-3 py-1 text-xs font-semibold text-primary-600">
                  {ex.muscle}
                </span>
                <h2 className="mt-3 text-lg font-bold text-gray-900 group-hover:text-primary-600">
                  {ex.name}
                </h2>
                <p className="mt-2 text-sm leading-relaxed text-gray-500">{ex.description}</p>
                <span className="mt-4 block text-sm font-semibold text-primary-500 group-hover:underline">
                  Ver como fazer →
                </span>
              </Link>
            ))}
          </div>
        </div>
      </section>

      <CTASection
        title="Monte um treino com esses exercícios"
        subtitle="A IA da EasyHealth cria um plano personalizado com os exercícios certos para o seu objetivo."
        ctaText="Criar meu treino"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}
